import Cocoa

// MARK: - Configuration

enum Config {
	static let defaultPollInterval: TimeInterval = 60
	static let paceThreshold: Double = 20.0
	static let baseURL = "https://claude.ai/api"
	static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
	static let cookieDefaultLifetimeDays = 30
	static var prefsPath: String { (configDir as NSString).appendingPathComponent("prefs.json") }

	static let configDir: String = {
		let home = NSHomeDirectory()
		return (home as NSString).appendingPathComponent(".config/claude-usage")
	}()
	static var sessionKeyPath: String { (configDir as NSString).appendingPathComponent("session-key") }
	static var orgIdPath: String { (configDir as NSString).appendingPathComponent("org-id") }
	static var sessionExpiryPath: String { (configDir as NSString).appendingPathComponent("session-expiry") }
	static var latestPath: String { (configDir as NSString).appendingPathComponent("latest.json") }
}

// MARK: - API Models

struct UsageLimitResponse: Decodable {
	let utilization: Double
	let resetsAt: String?

	enum CodingKeys: String, CodingKey {
		case utilization
		case resetsAt = "resets_at"
	}
}

struct UsageAPIResponse: Decodable {
	let fiveHour: UsageLimitResponse
	let sevenDay: UsageLimitResponse
	let sevenDaySonnet: UsageLimitResponse?

	enum CodingKeys: String, CodingKey {
		case fiveHour = "five_hour"
		case sevenDay = "seven_day"
		case sevenDaySonnet = "seven_day_sonnet"
	}
}

struct Organization: Decodable {
	let uuid: String
	let name: String
}

// MARK: - Preferences

struct Prefs: Codable {
	var pollIntervalSeconds: Int = 60
	var displayPercentsInMenubar: Bool = true
	var showSonnet: Bool = false
	var yellowEnabled: Bool = true
	var yellowDays: Int = 3
	var redEnabled: Bool = true
	var redDays: Int = 0

	static func load() -> Prefs {
		guard let data = FileManager.default.contents(atPath: Config.prefsPath),
			  let p = try? JSONDecoder().decode(Prefs.self, from: data) else {
			return Prefs()
		}
		return p
	}

	func save() {
		CredentialStore.ensureDir()
		if let data = try? JSONEncoder().encode(self) {
			try? data.write(to: URL(fileURLWithPath: Config.prefsPath))
		}
	}
}

// MARK: - Credential Store

enum CredentialStore {
	static func ensureDir() {
		try? FileManager.default.createDirectory(
			atPath: Config.configDir,
			withIntermediateDirectories: true
		)
	}

	static func readSessionKey() -> String? {
		read(Config.sessionKeyPath)
	}

	static func readOrgId() -> String? {
		read(Config.orgIdPath)
	}

	static var hasCredentials: Bool {
		readSessionKey() != nil && readOrgId() != nil
	}

	static func saveSessionKey(_ key: String) {
		ensureDir()
		write(key, to: Config.sessionKeyPath)
	}

	static func saveOrgId(_ orgId: String) {
		ensureDir()
		write(orgId, to: Config.orgIdPath)
	}

	static func save(sessionKey: String, orgId: String) {
		saveSessionKey(sessionKey)
		saveOrgId(orgId)
	}

	static func updateSessionKey(_ key: String) {
		ensureDir()
		write(key, to: Config.sessionKeyPath)
	}

	// MARK: Session expiry tracking

	static func saveSessionExpiry(_ date: Date) {
		ensureDir()
		let str = ISO8601DateFormatter().string(from: date)
		write(str, to: Config.sessionExpiryPath)
	}

	/// Days remaining until session key expires, or nil if unknown
	static func sessionKeyDaysRemaining() -> Int? {
		// Try stored expiry first
		if let str = read(Config.sessionExpiryPath),
		   let expiry = parseExpiry(str) {
			return Calendar.current.dateComponents(
				[.day], from: Date(), to: expiry
			).day
		}
		// Fallback: estimate from file age + assumed 30d lifetime
		guard let attrs = try? FileManager.default.attributesOfItem(
			atPath: Config.sessionKeyPath
		), let modified = attrs[.modificationDate] as? Date else {
			return nil
		}
		let estimated = modified.addingTimeInterval(
			Double(Config.cookieDefaultLifetimeDays) * 86400
		)
		return Calendar.current.dateComponents(
			[.day], from: Date(), to: estimated
		).day
	}

	private static func parseExpiry(_ str: String) -> Date? {
		let fmt = ISO8601DateFormatter()
		fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = fmt.date(from: str) { return d }
		fmt.formatOptions = [.withInternetDateTime]
		return fmt.date(from: str)
	}

	private static func read(_ path: String) -> String? {
		guard let data = FileManager.default.contents(atPath: path),
			  let str = String(data: data, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines),
			  !str.isEmpty else { return nil }
		return str
	}

	private static func write(_ value: String, to path: String) {
		try? value.write(toFile: path, atomically: true, encoding: .utf8)
		try? FileManager.default.setAttributes(
			[.posixPermissions: 0o600], ofItemAtPath: path
		)
	}
}

// MARK: - Org Discovery

enum OrgDiscovery {
	static func fetch(
		sessionKey: String,
		completion: @escaping (Result<String, Error>) -> Void
	) {
		let urlStr = "\(Config.baseURL)/organizations"
		guard let url = URL(string: urlStr) else {
			completion(.failure(NSError(domain: "OrgDiscovery", code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
			return
		}

		var req = URLRequest(url: url)
		req.httpMethod = "GET"
		req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
		req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
		req.setValue("application/json", forHTTPHeaderField: "Accept")
		req.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
		req.setValue("claude.ai", forHTTPHeaderField: "Origin")
		req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
		req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
		req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
		req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

		URLSession.shared.dataTask(with: req) { data, response, error in
			if let error = error {
				completion(.failure(error))
				return
			}

			guard let http = response as? HTTPURLResponse,
				  (200...299).contains(http.statusCode),
				  let data = data else {
				let code = (response as? HTTPURLResponse)?.statusCode ?? 0
				completion(.failure(NSError(domain: "OrgDiscovery", code: code,
					userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])))
				return
			}

			do {
				let orgs = try JSONDecoder().decode([Organization].self, from: data)
				guard let first = orgs.first else {
					completion(.failure(NSError(domain: "OrgDiscovery", code: 2,
						userInfo: [NSLocalizedDescriptionKey: "No organizations found"])))
					return
				}
				completion(.success(first.uuid))
			} catch {
				completion(.failure(error))
			}
		}.resume()
	}
}

// MARK: - Pace Calculator

struct PaceResult {
	let percentage: Int
	let color: NSColor
}

enum PaceCalculator {
	static func calculate(
		utilization: Double,
		resetsAt: String?,
		windowHours: Double,
		threshold: Double = Config.paceThreshold
	) -> PaceResult {
		let usagePercent = utilization
		let pct = Int(round(usagePercent))

		guard let resetsAt = resetsAt,
			  let resetDate = parseISO8601(resetsAt) else {
			// No reset time — color by absolute usage
			if usagePercent > 80 {
				return PaceResult(percentage: pct, color: .systemRed)
			} else if usagePercent > 50 {
				return PaceResult(percentage: pct, color: .systemYellow)
			}
			return PaceResult(percentage: pct, color: NSColor(srgbRed: 0.35, green: 0.75, blue: 0.35, alpha: 1.0))
		}

		let pace = computePace(resetDate: resetDate, windowHours: windowHours)
		let greenCeiling = pace * 0.75

		if usagePercent > pace {
			return PaceResult(percentage: pct, color: .systemRed)
		} else if usagePercent > greenCeiling {
			return PaceResult(percentage: pct, color: .systemYellow)
		} else {
			return PaceResult(percentage: pct, color: NSColor(srgbRed: 0.35, green: 0.75, blue: 0.35, alpha: 1.0))
		}
	}

	static func pacePercent(resetsAt: String?, windowHours: Double) -> Int? {
		guard let resetsAt = resetsAt,
			  let resetDate = parseISO8601(resetsAt) else { return nil }
		return Int(round(computePace(resetDate: resetDate, windowHours: windowHours)))
	}

	private static func computePace(resetDate: Date, windowHours: Double) -> Double {
		let windowSeconds = windowHours * 3600
		let windowStart = resetDate.addingTimeInterval(-windowSeconds)
		let elapsed = Date().timeIntervalSince(windowStart)
		return min(max((elapsed / windowSeconds) * 100.0, 0), 100)
	}

	static func parseDate(_ string: String) -> Date? {
		parseISO8601(string)
	}

	private static func parseISO8601(_ string: String) -> Date? {
		let fmt = ISO8601DateFormatter()
		fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = fmt.date(from: string) { return d }
		fmt.formatOptions = [.withInternetDateTime]
		return fmt.date(from: string)
	}
}

// MARK: - Usage Poller

class UsagePoller {
	var onUpdate: ((UsageAPIResponse) -> Void)?
	var onError: ((String) -> Void)?

	private var timer: Timer?

	func start() {
		let interval = TimeInterval(Prefs.load().pollIntervalSeconds)
		poll()
		timer = Timer.scheduledTimer(
			withTimeInterval: interval > 0 ? interval : Config.defaultPollInterval, repeats: true
		) { [weak self] _ in
			self?.poll()
		}
	}

	func stop() {
		timer?.invalidate()
		timer = nil
	}

	func poll() {
		guard let sessionKey = CredentialStore.readSessionKey(),
			  let orgId = CredentialStore.readOrgId() else {
			onError?("Missing credentials")
			return
		}

		let urlStr = "\(Config.baseURL)/organizations/\(orgId)/usage"
		guard let url = URL(string: urlStr) else {
			onError?("Invalid URL")
			return
		}

		var req = URLRequest(url: url)
		req.httpMethod = "GET"
		req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
		req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
		req.setValue("application/json", forHTTPHeaderField: "Accept")
		req.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
		req.setValue("claude.ai", forHTTPHeaderField: "Origin")
		req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
		req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
		req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
		req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")

		URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
			if let error = error {
				DispatchQueue.main.async { self?.onError?(error.localizedDescription) }
				return
			}

			guard let http = response as? HTTPURLResponse else {
				DispatchQueue.main.async { self?.onError?("Invalid response") }
				return
			}

			// Cookie rotation: capture rotated sessionKey
			self?.handleCookieRotation(http)

			guard (200...299).contains(http.statusCode) else {
				let msg: String
				switch http.statusCode {
				case 401: msg = "Auth failed — update session key"
				case 403: msg = "Forbidden — check org ID"
				case 429: msg = "Rate limited"
				default: msg = "HTTP \(http.statusCode)"
				}
				DispatchQueue.main.async { self?.onError?(msg) }
				return
			}

			guard let data = data else {
				DispatchQueue.main.async { self?.onError?("No data") }
				return
			}

			do {
				let usage = try JSONDecoder().decode(UsageAPIResponse.self, from: data)
				DispatchQueue.main.async { self?.onUpdate?(usage) }
			} catch {
				DispatchQueue.main.async {
					self?.onError?("Parse error: \(error.localizedDescription)")
				}
			}
		}.resume()
	}

	private func handleCookieRotation(_ response: HTTPURLResponse) {
		guard let headers = response.allHeaderFields as? [String: String],
			  let url = response.url else { return }

		let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
		for cookie in cookies where cookie.name == "sessionKey" {
			let value = cookie.value
			if value.hasPrefix("sk-ant-") {
				CredentialStore.updateSessionKey(value)
				if let expiry = cookie.expiresDate {
					CredentialStore.saveSessionExpiry(expiry)
				}
			}
		}
	}
}

// MARK: - Menu Bar Icon

enum MenuBarIcon {
	/// Claude-inspired sparkle icon for menu bar (18x18 template)
	static func sparkle() -> NSImage {
		let size: CGFloat = 18
		let img = NSImage(size: NSSize(width: size, height: size))
		img.lockFocus()
		if let ctx = NSGraphicsContext.current?.cgContext {
			ctx.setFillColor(CGColor(gray: 1, alpha: 1))

			let cx = size / 2
			let cy = size / 2

			// Four-pointed sparkle with curved sides
			// Each point is a diamond-ish petal drawn with bezier curves
			let outer: CGFloat = 7.5   // tip distance from center
			let inner: CGFloat = 2.2   // waist width (how pinched)
			let ctrl: CGFloat = 1.0    // control point offset (curves the sides)

			let path = NSBezierPath()

			// Top point
			path.move(to: NSPoint(x: cx, y: cy + outer))
			path.curve(to: NSPoint(x: cx + inner, y: cy),
					   controlPoint1: NSPoint(x: cx + ctrl, y: cy + outer * 0.45),
					   controlPoint2: NSPoint(x: cx + inner, y: cy + ctrl))
			// Right point
			path.curve(to: NSPoint(x: cx + outer, y: cy),
					   controlPoint1: NSPoint(x: cx + inner, y: cy + ctrl * 0.5),
					   controlPoint2: NSPoint(x: cx + outer * 0.45, y: cy + ctrl * 0.3))
			path.curve(to: NSPoint(x: cx + inner, y: cy),
					   controlPoint1: NSPoint(x: cx + outer * 0.45, y: cy - ctrl * 0.3),
					   controlPoint2: NSPoint(x: cx + inner, y: cy - ctrl * 0.5))
			// Bottom point
			path.curve(to: NSPoint(x: cx, y: cy - outer),
					   controlPoint1: NSPoint(x: cx + inner, y: cy - ctrl),
					   controlPoint2: NSPoint(x: cx + ctrl, y: cy - outer * 0.45))
			path.curve(to: NSPoint(x: cx - inner, y: cy),
					   controlPoint1: NSPoint(x: cx - ctrl, y: cy - outer * 0.45),
					   controlPoint2: NSPoint(x: cx - inner, y: cy - ctrl))
			// Left point
			path.curve(to: NSPoint(x: cx - outer, y: cy),
					   controlPoint1: NSPoint(x: cx - inner, y: cy - ctrl * 0.5),
					   controlPoint2: NSPoint(x: cx - outer * 0.45, y: cy - ctrl * 0.3))
			path.curve(to: NSPoint(x: cx - inner, y: cy),
					   controlPoint1: NSPoint(x: cx - outer * 0.45, y: cy + ctrl * 0.3),
					   controlPoint2: NSPoint(x: cx - inner, y: cy + ctrl * 0.5))
			// Back to top
			path.curve(to: NSPoint(x: cx, y: cy + outer),
					   controlPoint1: NSPoint(x: cx - inner, y: cy + ctrl),
					   controlPoint2: NSPoint(x: cx - ctrl, y: cy + outer * 0.45))

			path.fill()
		}
		img.unlockFocus()
		img.isTemplate = true
		return img
	}
}

// MARK: - Status Bar Controller

class StatusBarController: NSObject {
	private let statusItem: NSStatusItem
	private let poller = UsagePoller()
	private var lastUsage: UsageAPIResponse?

	private let menuFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
	private let timeFmt: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "h:mm a"
		f.timeZone = TimeZone(identifier: "America/Los_Angeles")
		return f
	}()

	override init() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		super.init()

		if let button = statusItem.button {
			button.image = MenuBarIcon.sparkle()
			button.imagePosition = .imageLeading
		}

		buildMenu()
		statusItem.button?.title = "..."

		poller.onUpdate = { [weak self] usage in
			self?.lastUsage = usage
			self?.render(usage)
			Self.writeLatest(usage)
		}

		poller.onError = { [weak self] error in
			self?.statusItem.button?.title = "\u{26A0}\u{FE0F}"
			self?.statusItem.button?.toolTip = error
			self?.statusItem.menu?.item(withTag: 100)?.title = "Error: \(error)"
		}

		poller.start()
	}

	private func buildMenu() {
		let menu = NSMenu()

		let fiveHourItem = NSMenuItem(title: "5h: --", action: nil, keyEquivalent: "")
		fiveHourItem.tag = 100
		menu.addItem(fiveHourItem)

		let sevenDayItem = NSMenuItem(title: "7d: --", action: nil, keyEquivalent: "")
		sevenDayItem.tag = 102
		menu.addItem(sevenDayItem)

		let sonnetItem = NSMenuItem(title: "sonnet: --", action: nil, keyEquivalent: "")
		sonnetItem.tag = 103
		sonnetItem.isHidden = !Prefs.load().showSonnet
		menu.addItem(sonnetItem)

		menu.addItem(.separator())

		let cookieAge = NSMenuItem(title: "", action: nil, keyEquivalent: "")
		cookieAge.tag = 101
		cookieAge.isHidden = true
		menu.addItem(cookieAge)

		let updated = NSMenuItem(
			title: "Updated: --", action: #selector(doRefresh), keyEquivalent: ""
		)
		updated.target = self
		updated.tag = 104
		menu.addItem(updated)

		menu.addItem(.separator())

		let settings = NSMenuItem(
			title: "Settings...", action: #selector(openSettings), keyEquivalent: ""
		)
		settings.target = self
		menu.addItem(settings)

		let quit = NSMenuItem(
			title: "Quit", action: #selector(doQuit), keyEquivalent: ""
		)
		quit.keyEquivalentModifierMask = .command
		quit.target = self
		menu.addItem(quit)

		statusItem.menu = menu
	}

	private func render(_ usage: UsageAPIResponse) {
		let daily = PaceCalculator.calculate(
			utilization: usage.fiveHour.utilization,
			resetsAt: usage.fiveHour.resetsAt,
			windowHours: 5.0
		)
		let weekly = PaceCalculator.calculate(
			utilization: usage.sevenDay.utilization,
			resetsAt: usage.sevenDay.resetsAt,
			windowHours: 168.0
		)

		// Menu bar attributed string
		let base: [NSAttributedString.Key: Any] = [
			.font: menuFont,
			.baselineOffset: -1,
		]
		let str = NSMutableAttributedString()

		str.append(NSAttributedString(string: " D", attributes: base))
		str.append(colored("\(daily.percentage)%", daily.color, base))

		str.append(NSAttributedString(string: " ", attributes: base))

		str.append(NSAttributedString(string: "W", attributes: base))
		str.append(colored("\(weekly.percentage)%", weekly.color, base))

		// Cookie expiry warning in menu bar
		let prefs = Prefs.load()
		if let remaining = CredentialStore.sessionKeyDaysRemaining() {
			if prefs.redEnabled && remaining <= prefs.redDays {
				str.append(NSAttributedString(string: " \u{1F534}", attributes: base))
			} else if prefs.yellowEnabled && remaining <= prefs.yellowDays {
				str.append(NSAttributedString(string: " \u{1F7E0}", attributes: base))
			}
		}

		statusItem.button?.attributedTitle = Prefs.load().displayPercentsInMenubar ? str : NSAttributedString(string: "")

		// Tooltip
		let dp = PaceCalculator.pacePercent(
			resetsAt: usage.fiveHour.resetsAt, windowHours: 5.0
		).map { "\($0)%" } ?? "??"
		let wp = PaceCalculator.pacePercent(
			resetsAt: usage.sevenDay.resetsAt, windowHours: 168.0
		).map { "\($0)%" } ?? "??"
		var tip = "5h: \(daily.percentage)% (pace: \(dp))\n" +
			"7d: \(weekly.percentage)% (pace: \(wp))"
		if let remaining = CredentialStore.sessionKeyDaysRemaining() {
			if (prefs.redEnabled && remaining <= prefs.redDays) ||
			   (prefs.yellowEnabled && remaining <= prefs.yellowDays) {
				tip += "\n\nSession key expires in \(remaining)d — refresh soon"
			}
		}
		statusItem.button?.toolTip = tip

		// Menu detail lines
		let fiveRemain = timeRemaining(resetsAt: usage.fiveHour.resetsAt, fine: true)
		statusItem.menu?.item(withTag: 100)?.title =
			"5h: \(daily.percentage)%\(fiveRemain)"

		let sevenRemain = timeRemaining(resetsAt: usage.sevenDay.resetsAt, fine: false)
		statusItem.menu?.item(withTag: 102)?.title =
			"7d: \(weekly.percentage)%\(sevenRemain)"

		// Sonnet (tag 103) — shown when enabled in prefs and data present
		if let sonnetItem = statusItem.menu?.item(withTag: 103) {
			let prefs = Prefs.load()
			if prefs.showSonnet, let sonnet = usage.sevenDaySonnet {
				let s = PaceCalculator.calculate(
					utilization: sonnet.utilization,
					resetsAt: sonnet.resetsAt,
					windowHours: 168.0
				)
				let sRemain = timeRemaining(resetsAt: sonnet.resetsAt, fine: false)
				sonnetItem.title = "sonnet: \(s.percentage)%\(sRemain)"
				sonnetItem.isHidden = false
			} else {
				sonnetItem.isHidden = true
			}
		}

		// Last updated timestamp (tag 104) — clickable to refresh
		statusItem.menu?.item(withTag: 104)?.title = "Updated: \(timeFmt.string(from: Date()))"

		// Cookie age menu item
		updateCookieAgeItem()
	}

	private func updateCookieAgeItem() {
		guard let item = statusItem.menu?.item(withTag: 101) else { return }
		guard let remaining = CredentialStore.sessionKeyDaysRemaining() else {
			item.isHidden = true
			return
		}

		let prefs = Prefs.load()
		item.isHidden = false
		if prefs.redEnabled && remaining <= prefs.redDays {
			item.title = "\u{1F534} Session key expires in \(remaining)d — replace now!"
		} else if prefs.yellowEnabled && remaining <= prefs.yellowDays {
			item.title = "\u{1F7E0} Session key expires in \(remaining)d — refresh soon"
		} else {
			item.title = "Session key: \(remaining)d remaining"
		}
	}

	private func colored(
		_ text: String, _ color: NSColor,
		_ base: [NSAttributedString.Key: Any]
	) -> NSAttributedString {
		var attrs = base
		attrs[.foregroundColor] = color
		return NSAttributedString(string: text, attributes: attrs)
	}

	/// Format time remaining until reset.
	/// fine: true = "2h 34m remain", false = "2d 3h remain"
	private func timeRemaining(resetsAt: String?, fine: Bool) -> String {
		guard let str = resetsAt,
			  let reset = PaceCalculator.parseDate(str) else {
			return ""
		}
		let secs = reset.timeIntervalSince(Date())
		guard secs > 0 else { return " -- reset" }

		let totalMin = Int(secs) / 60
		let hours = totalMin / 60
		let mins = totalMin % 60
		let days = hours / 24
		let remHours = hours % 24

		let str2: String
		if fine {
			if hours > 0 {
				str2 = "\(hours)h \(String(format: "%02d", mins))m"
			} else {
				str2 = "\(mins)m"
			}
		} else {
			if days > 0 {
				str2 = "\(days)d \(remHours)h"
			} else {
				str2 = "\(remHours)h"
			}
		}
		return "  —  \(str2) remain"
	}

	private static func writeLatest(_ usage: UsageAPIResponse) {
		let fmt = DateFormatter()
		fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
		fmt.timeZone = TimeZone(identifier: "America/Los_Angeles")

		var dict: [String: Any] = [
			"v": 1,
			"updated_at": fmt.string(from: Date()),
			"five_hour": [
				"utilization": usage.fiveHour.utilization,
				"resets_at": usage.fiveHour.resetsAt as Any,
			],
			"seven_day": [
				"utilization": usage.sevenDay.utilization,
				"resets_at": usage.sevenDay.resetsAt as Any,
			],
		]
		if let sonnet = usage.sevenDaySonnet {
			dict["seven_day_sonnet"] = [
				"utilization": sonnet.utilization,
				"resets_at": sonnet.resetsAt as Any,
			]
		}

		CredentialStore.ensureDir()
		if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
			try? data.write(to: URL(fileURLWithPath: Config.latestPath), options: .atomic)
			// 0o644 — world-readable, non-sensitive data
			try? FileManager.default.setAttributes(
				[.posixPermissions: 0o644], ofItemAtPath: Config.latestPath
			)
		}
	}

	@objc private func doRefresh() {
		statusItem.button?.title = "..."
		poller.poll()
	}

	@objc private func openSettings() {
		showSetupDialog()
		poller.poll()
	}

	@objc private func doQuit() {
		poller.stop()
		NSApp.terminate(nil)
	}
}

// MARK: - Stepper Helpers

class ExpiryStepperDelegate: NSObject {
	let daysField: NSTextField
	let dateLabel: NSTextField
	private let dateFmt: DateFormatter = {
		let f = DateFormatter()
		f.dateStyle = .medium
		f.timeStyle = .none
		return f
	}()

	init(daysField: NSTextField, dateLabel: NSTextField) {
		self.daysField = daysField
		self.dateLabel = dateLabel
	}

	@objc func stepperChanged(_ sender: NSStepper) {
		daysField.integerValue = sender.integerValue
		updateDateLabel(days: sender.integerValue)
	}

	func updateDateLabel(days: Int) {
		let target = Calendar.current.date(
			byAdding: .day, value: days, to: Date()
		) ?? Date()
		dateLabel.stringValue = dateFmt.string(from: target)
	}
}

class SimpleStepperDelegate: NSObject {
	let field: NSTextField

	init(field: NSTextField) {
		self.field = field
	}

	@objc func stepperChanged(_ sender: NSStepper) {
		field.integerValue = sender.integerValue
	}
}

// MARK: - Integration Info

class IntegrationInfoHandler: NSObject {
	static let shared = IntegrationInfoHandler()

	@objc func showInfo() {
		let info = NSAlert()
		info.messageText = "Integration"
		info.informativeText = """
			After each poll, usage data is written to:
			~/.config/claude-usage/latest.json

			Schema (v1):
			{
			  "v": 1,
			  "updated_at": "2026-03-17T14:32:00-07:00",
			  "five_hour": { "utilization": 42.5, "resets_at": "..." },
			  "seven_day": { "utilization": 15.3, "resets_at": "..." },
			  "seven_day_sonnet": { "utilization": 8.1, "resets_at": "..." }
			}

			• utilization: 0–100 (percentage)
			• resets_at: UTC ISO 8601
			• updated_at: Pacific time
			• seven_day_sonnet: optional
			• File is atomic, 0644, updated every 60s

			Shell: jq '.five_hour.utilization' ~/.config/claude-usage/latest.json
			"""
		info.alertStyle = .informational
		info.addButton(withTitle: "OK")
		info.window.level = .floating
		info.runModal()
	}
}

// MARK: - Setup Dialog

func showSetupDialog(requireKey: Bool = false) {
	NSApp.activate(ignoringOtherApps: true)

	let prefs = Prefs.load()
	let alert = NSAlert()
	alert.messageText = "Claude Usage Settings"
	alert.informativeText =
		"Enter your session key from claude.ai.\n\n" +
		"Find it in browser DevTools:\n" +
		"  Application > Cookies > claude.ai > sessionKey\n\n" +
		"The org ID will be discovered automatically."
	alert.alertStyle = .informational

	// Keep references alive during modal
	var helpers: [AnyObject] = []

	let w: CGFloat = 420
	let height: CGFloat = 244
	let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: height))
	var y = height

	// --- Session key ---
	y -= 22
	let keyLabel = NSTextField(labelWithString: "Session Key:")
	keyLabel.frame = NSRect(x: 0, y: y, width: 95, height: 22)
	container.addSubview(keyLabel)

	let keyField = NSSecureTextField(frame: NSRect(x: 100, y: y, width: w - 100, height: 22))
	keyField.placeholderString = "sk-ant-sid01-..."
	container.addSubview(keyField)

	// --- Divider ---
	y -= 16
	let div1 = NSBox(frame: NSRect(x: 0, y: y, width: w, height: 1))
	div1.boxType = .separator
	container.addSubview(div1)

	// --- Expires in ---
	y -= 26
	let expiryLabel = NSTextField(labelWithString: "Expires in:")
	expiryLabel.frame = NSRect(x: 0, y: y, width: 95, height: 22)
	container.addSubview(expiryLabel)

	let initialDays = CredentialStore.sessionKeyDaysRemaining()
		?? Config.cookieDefaultLifetimeDays

	let expiryDaysField = NSTextField(frame: NSRect(x: 100, y: y, width: 40, height: 22))
	expiryDaysField.integerValue = initialDays
	expiryDaysField.alignment = .center
	expiryDaysField.isEditable = false
	expiryDaysField.isSelectable = false
	container.addSubview(expiryDaysField)

	let daysLabel = NSTextField(labelWithString: "days")
	daysLabel.frame = NSRect(x: 144, y: y, width: 35, height: 22)
	container.addSubview(daysLabel)

	let es = NSStepper(frame: NSRect(x: 180, y: y, width: 19, height: 22))
	es.minValue = 0
	es.maxValue = 90
	es.integerValue = initialDays
	es.increment = 1
	es.valueWraps = false
	container.addSubview(es)

	let dateLabel = NSTextField(labelWithString: "")
	dateLabel.frame = NSRect(x: 210, y: y, width: 200, height: 22)
	dateLabel.textColor = .secondaryLabelColor
	container.addSubview(dateLabel)

	let expiryDelegate = ExpiryStepperDelegate(
		daysField: expiryDaysField, dateLabel: dateLabel
	)
	es.target = expiryDelegate
	es.action = #selector(ExpiryStepperDelegate.stepperChanged(_:))
	expiryDelegate.updateDateLabel(days: initialDays)
	helpers.append(expiryDelegate)

	// --- Yellow warning (indented to align with days field at x:100) ---
	y -= 28
	let yCheck = NSButton(checkboxWithTitle: "Yellow warning", target: nil, action: nil)
	yCheck.frame = NSRect(x: 100, y: y, width: 130, height: 22)
	yCheck.state = prefs.yellowEnabled ? .on : .off
	container.addSubview(yCheck)

	let yField = NSTextField(frame: NSRect(x: 238, y: y, width: 34, height: 22))
	yField.integerValue = prefs.yellowDays
	yField.alignment = .center
	yField.isEditable = false
	yField.isSelectable = false
	container.addSubview(yField)

	let ys = NSStepper(frame: NSRect(x: 276, y: y, width: 19, height: 22))
	ys.minValue = 0
	ys.maxValue = 30
	ys.integerValue = prefs.yellowDays
	ys.increment = 1
	ys.valueWraps = false
	container.addSubview(ys)

	let yLabel = NSTextField(labelWithString: "days before")
	yLabel.frame = NSRect(x: 300, y: y, width: 100, height: 22)
	container.addSubview(yLabel)

	let yDelegate = SimpleStepperDelegate(field: yField)
	ys.target = yDelegate
	ys.action = #selector(SimpleStepperDelegate.stepperChanged(_:))
	helpers.append(yDelegate)

	// --- Red warning (indented to align with days field at x:100) ---
	y -= 28
	let rCheck = NSButton(checkboxWithTitle: "Red warning", target: nil, action: nil)
	rCheck.frame = NSRect(x: 100, y: y, width: 130, height: 22)
	rCheck.state = prefs.redEnabled ? .on : .off
	container.addSubview(rCheck)

	let rField = NSTextField(frame: NSRect(x: 238, y: y, width: 34, height: 22))
	rField.integerValue = prefs.redDays
	rField.alignment = .center
	rField.isEditable = false
	rField.isSelectable = false
	container.addSubview(rField)

	let rs = NSStepper(frame: NSRect(x: 276, y: y, width: 19, height: 22))
	rs.minValue = 0
	rs.maxValue = 30
	rs.integerValue = prefs.redDays
	rs.increment = 1
	rs.valueWraps = false
	container.addSubview(rs)

	let rLabel = NSTextField(labelWithString: "days before")
	rLabel.frame = NSRect(x: 300, y: y, width: 100, height: 22)
	container.addSubview(rLabel)

	let rDelegate = SimpleStepperDelegate(field: rField)
	rs.target = rDelegate
	rs.action = #selector(SimpleStepperDelegate.stepperChanged(_:))
	helpers.append(rDelegate)

	// --- Divider ---
	y -= 16
	let div2 = NSBox(frame: NSRect(x: 0, y: y, width: w, height: 1))
	div2.boxType = .separator
	container.addSubview(div2)

	// --- Show Sonnet ---
	y -= 26
	let sCheck = NSButton(checkboxWithTitle: "Show Sonnet in menu", target: nil, action: nil)
	sCheck.frame = NSRect(x: 0, y: y, width: 200, height: 22)
	sCheck.state = prefs.showSonnet ? .on : .off
	container.addSubview(sCheck)

	// --- Divider ---
	y -= 16
	let div3 = NSBox(frame: NSRect(x: 0, y: y, width: w, height: 1))
	div3.boxType = .separator
	container.addSubview(div3)

	// --- Integration info ---
	y -= 26
	let infoLabel = NSTextField(labelWithString: "File IPC: ~/.config/claude-usage/latest.json")
	infoLabel.frame = NSRect(x: 0, y: y, width: 300, height: 22)
	infoLabel.textColor = .secondaryLabelColor
	infoLabel.font = NSFont.systemFont(ofSize: 11)
	container.addSubview(infoLabel)

	let infoBtn = NSButton(frame: NSRect(x: 310, y: y, width: 110, height: 22))
	infoBtn.title = "Integration Info"
	infoBtn.bezelStyle = .inline
	infoBtn.target = IntegrationInfoHandler.shared
	infoBtn.action = #selector(IntegrationInfoHandler.showInfo)
	container.addSubview(infoBtn)

	alert.accessoryView = container
	alert.addButton(withTitle: "Save")
	alert.addButton(withTitle: requireKey ? "Quit" : "Cancel")

	alert.window.level = .floating

	let response = alert.runModal()
	if response == .alertFirstButtonReturn {
		let key = keyField.stringValue
			.trimmingCharacters(in: .whitespacesAndNewlines)

		// Save expiry
		let expiry = Calendar.current.date(
			byAdding: .day, value: es.integerValue, to: Date()
		) ?? Date()
		CredentialStore.saveSessionExpiry(expiry)

		// Save prefs
		var newPrefs = Prefs.load() // preserve pollIntervalSeconds from file
		newPrefs.showSonnet = sCheck.state == .on
		newPrefs.yellowEnabled = yCheck.state == .on
		newPrefs.yellowDays = ys.integerValue
		newPrefs.redEnabled = rCheck.state == .on
		newPrefs.redDays = rs.integerValue
		newPrefs.save()

		if !key.isEmpty {
			CredentialStore.saveSessionKey(key)
			discoverOrg(sessionKey: key)
		} else if requireKey {
			let err = NSAlert()
			err.messageText = "Session key is required"
			err.alertStyle = .warning
			err.runModal()
			showSetupDialog(requireKey: true)
		}
	} else if requireKey {
		NSApp.terminate(nil)
	}

	_ = helpers
}

func discoverOrg(sessionKey: String) {
	let spinner = NSAlert()
	spinner.messageText = "Discovering organization..."
	spinner.informativeText = "Fetching org ID from claude.ai"
	spinner.addButton(withTitle: "Cancel")
	spinner.window.level = .floating

	var done = false

	OrgDiscovery.fetch(sessionKey: sessionKey) { result in
		done = true
		DispatchQueue.main.async {
			NSApp.stopModal()

			switch result {
			case .success(let uuid):
				CredentialStore.saveOrgId(uuid)
			case .failure(let error):
				let err = NSAlert()
				err.messageText = "Could not discover org ID"
				err.informativeText =
					"\(error.localizedDescription)\n\n" +
					"You can enter it manually in Settings."
				err.alertStyle = .warning
				err.runModal()
			}
		}
	}

	DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
		if !done {
			spinner.runModal()
		}
	}
}

// MARK: - Edit Menu (enables Cmd+V in text fields)

func installEditMenu() {
	let mainMenu = NSMenu()

	let editMenuItem = NSMenuItem()
	editMenuItem.submenu = {
		let m = NSMenu(title: "Edit")
		m.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		m.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		m.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		return m
	}()
	mainMenu.addItem(editMenuItem)

	NSApp.mainMenu = mainMenu
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
	var controller: StatusBarController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		installEditMenu()
		if !CredentialStore.hasCredentials {
			showSetupDialog(requireKey: true)
		}
		controller = StatusBarController()
	}
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
