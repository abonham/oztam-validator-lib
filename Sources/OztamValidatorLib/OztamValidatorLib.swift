import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum URLError: Error {
    case badURL
}


public extension Optional where Wrapped: Codable {
    init?(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            self = .none
            return
        }
        self = try? container.decode(Wrapped.self)
    }
}

public struct MeterEvent: Codable {
    public let events: [Event]
    public let secondsViewed: Double
    public let oztamFlags: [String: Bool]?

    public var firstEvent: Event? { events.first }

    public var eventDescription: String {
        "\(events[0].description)\nprogress: \(secondsViewed)"
    }
}

public struct Event: Codable {
    public enum EventType: String, Codable {
        case LOAD
        case BEGIN
        case AD_BEGIN
        case AD_COMPLETE
        case PROGRESS
        case COMPLETE
    }

    public let event: EventType
    public let fromPosition: Double
    public let toPosition: Double
    public let timestamp: Date

    public var progressTotal: Double { toPosition - fromPosition }

    public var description: String {
        "\(event.rawValue)\nfrom: \(fromPosition)\nto: \(toPosition)\nat: \(timestamp)"
    }
}

public enum EventError: Error {
    case progressTooLong(Event, Double)
    case negativeProgress(Event, Double)
    case outOfOrder(Event, Event)
    case timestampsOutOfOrder(Event, Event)
    case noEvents
    case multipleLoad
    case multipleBegin
    case noLoad
    case noBegin
    case adEventProgressNonZero(Event, Double)

    public var description: String {
        switch self {
        case .progressTooLong(let event, let time):
            return "Progress event must be 60 seconds or less, time was \(time) for \(event.event.rawValue) event at \(event.timestamp)"
        case .negativeProgress(let event, let time):
            return "Progress must be positive, time was \(time) for \(event.event.rawValue) event at \(event.timestamp)"
        case let .outOfOrder(first, second):
            return """
\(first.event.rawValue) event must not be immediately followed by a \(second.event.rawValue) event.
First Event: \(first.description)

Second Event: \(second.description)
"""
        case let .timestampsOutOfOrder(first, second):
            return "Timestamps for events are out of order:\n \(first.description)\n\(second.description)"
        case .noEvents: return "No oztail events"
        case .multipleLoad: return "There must olny be one load event per session"
        case .multipleBegin: return "There must olny be one begin event per session"
        case .noLoad: return "No load event"
        case .noBegin: return "No begin event"
        case .adEventProgressNonZero(let event, let time): return "Ad progress must be 0, time was \(time) for \(event.event.rawValue) event at \(event.timestamp)"
        }
    }
}

public enum ValidationError: Error { 
	case errors([EventError])
}

public struct Oztail {
    let host = "oztam.com.au"

    func url(_ subdomain: String, sessionId: String) throws -> URL {
        let base = "https://\(userName):\(password)@\(subdomain).\(host)/api/events/sessions"
        guard var components = URLComponents(string: base) else { throw URLError.badURL }
        let query = URLQueryItem(name: "sessionId", value: sessionId)
        components.queryItems = [query]
        guard let url = components.url else { throw URLError.badURL }
        
        return url
    }

    var userName: String
    var password: String
    var debug: Bool = false
    var verbose: Bool = false

    var subdomain: String {
        return debug ? "stail" : "tail"
    }

    public func retrieveSession(_ sessionId: String) throws -> [MeterEvent] {
        let fetchURL = try url(subdomain, sessionId: sessionId)
        let data = try Data(contentsOf: fetchURL)

        let formatter = ISO8601DateFormatter.init()
        formatter.formatOptions.insert(.withFractionalSeconds)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom {
            let string = try $0.singleValueContainer().decode(String.self)
            return formatter.date(from: string)!
        }
        let object = try decoder.decode([MeterEvent].self, from: data)

        guard !object.isEmpty else { throw EventError.noEvents }
        return object
    }

    public func fetch(_ sessionId: String) throws -> Result<Bool, Error> {
        let object = try retrieveSession(sessionId)
        var hasErrors = false

        print("\u{001B}[1mChecking load and begin events\u{001B}[0m")
        do {
            try validateOneOffEvents(events: object)
            print("\u{001B}[32mAll init events OK\u{001B}[0m")
        } catch {
            hasErrors = true
            print("\((error as? EventError)?.description ?? "WFT")")
        }
        print()

        print("\u{001B}[1mChecking event sequences\u{001B}[0m")
        var failed = false
        for eventPair in sequence(state: object.makeIterator(), next: { it in
            it.next().map { return ($0, it.map { $0 }.first) }
        }) {
            do {
                try validateEventPair(eventPair)
            } catch {
                hasErrors = true
                failed = true
                print("\u{001B}[31m\((error as? EventError)?.description ?? "WFT")\u{001B}[0m")
            }
        }
        if !failed { print("\u{001B}[32mAll events in correct sequence\u{001B}[0m") }
        print()

        print("\u{001B}[1mChecking progress events\u{001B}[0m")
        let progressErrors = validateProgressTimes(events: object)
        if !progressErrors.isEmpty {
            print("\u{001B}[31mError: some progress events are incorrect\u{001B}[0m")
            print(progressErrors.map(\.eventDescription).joined(separator: "\n\n"))
            hasErrors = true
        } else {
            print("\u{001B}[32mAll events <= 60 seconds\u{001B}[0m")
        }
        print()

        print("\u{001B}[1mChecking ad events\u{001B}[0m")
        let adErrors = validateAdEvents(events: object)
        if !adErrors.isEmpty {
            print("\u{001B}[31mAd error: start and finish times do not match\u{001B}[0m")
            print(adErrors.map(\.eventDescription).joined(separator: "\n\n"))
        } else {
            print("\u{001B}[32mAll ad events are correct\u{001B}[0m")
        }

        print()
        if hasErrors {
            print("\u{001B}[31mValidation FAILED\u{001B}[0m")
        } else {
            print("\u{001B}[32mBasic validation PASSED\u{001B}[0m")
        }

		return Result<Bool, Error>.success(!hasErrors)
    }

    public func validate(meterEvents events: [MeterEvent]) throws -> Result<Bool, Error> {
        return Result {
            var failedEvents = [MeterEvent]()
            failedEvents += validateProgressTimes(events: events)
            failedEvents += validateAdEvents(events: events)
            try validateOneOffEvents(events: events)
            return !failedEvents.isEmpty
        }
    }

    public func startingEventsErrors(for events: [MeterEvent])  -> [EventError] {
        var errors = [EventError]()

        let allEvents = events.map { $0.events.first!.event }
        let loadEvents = allEvents.filter({ $0 == .LOAD })
        if loadEvents.count > 1 { errors.append(.multipleLoad) }
        if loadEvents.isEmpty { errors.append(.noLoad) }
        let beginEvents = allEvents.filter({ $0 == .BEGIN })
        if beginEvents.count > 1 { errors.append(.multipleBegin) }
        if beginEvents.isEmpty { errors.append(.noBegin) }

        return errors
    }

    public func progressTimeErrors(for events: [MeterEvent]) -> [EventError] {
        var failedEvents = [EventError]()
        let zeroTimeEvents = [Event.EventType.LOAD,
                              Event.EventType.BEGIN,
                              Event.EventType.AD_BEGIN,
                              Event.EventType.AD_COMPLETE,
                              Event.EventType.COMPLETE
        ]
        let progressEvents = events.compactMap { $0.firstEvent }
            .filter { !zeroTimeEvents.contains($0.event) }
        failedEvents += progressEvents.filter { $0.progressTotal <= 0 }
            .map { EventError.negativeProgress($0, $0.progressTotal) }
        failedEvents += events.filter { $0.oztamFlags != nil }.map { EventError.progressTooLong($0.firstEvent!, $0.firstEvent!.progressTotal)}
        return failedEvents
    }

    public func adEventProgressErrors(for events: [MeterEvent]) -> [EventError] {
        let adTypes = [Event.EventType.AD_BEGIN, Event.EventType.AD_COMPLETE]
        let adEvents = events.compactMap { return $0.firstEvent }
            .filter { adTypes.contains($0.event) }
        return adEvents.filter { $0.fromPosition != $0.toPosition }
            .map { EventError.adEventProgressNonZero($0, $0.progressTotal)}
    }

    public func validationErrors(for events: [MeterEvent]) -> [EventError] {
        var errors = [EventError]()

        errors += startingEventsErrors(for: events)
        errors += progressTimeErrors(for: events)
        errors += adEventProgressErrors(for: events)

        for eventPair in sequence(state: events.makeIterator(), next: { it in
            it.next().map { return ($0, it.map { $0 }.first) }
        }) {
            do {
                try validateEventPair(eventPair)
            } catch {
                errors.append(error as! EventError)
            }
        }

        return errors
    }

    func validateProgressTimes(events: [MeterEvent]) -> [MeterEvent] {
    	var failedEvents = [MeterEvent]()
		failedEvents += events.filter { $0.events[0].toPosition <  $0.events[0].fromPosition }
		failedEvents += events.filter { $0.oztamFlags != nil }
        return failedEvents
    }

    func validateAdEvents(events: [MeterEvent]) -> [MeterEvent] {
        let adEvents = events.filter { $0.events.first?.event == Event.EventType.AD_BEGIN || $0.events.first?.event == Event.EventType.AD_COMPLETE }
        return adEvents.filter {
            $0.events.first!.fromPosition != $0.events.first!.toPosition
        }
    }

    func validateOneOffEvents(events: [MeterEvent]) throws {
        let allEvents = events.map { $0.events.first!.event }
        guard allEvents.filter({ $0 == .LOAD }).count == 1 else { throw EventError.multipleLoad }
        guard allEvents.filter({ $0 == .BEGIN }).count == 1 else { throw EventError.multipleBegin }
    }

    func validateEventPair(_ pair: (firstEvent: MeterEvent, secondEvent: MeterEvent?)) throws {
        guard let firstEvent = pair.firstEvent.events.first,
            let secondEvent = pair.secondEvent?.events.first else { return }

        guard firstEvent.timestamp < secondEvent.timestamp else { throw EventError.timestampsOutOfOrder(firstEvent, secondEvent)}

        let first = firstEvent
        let second = secondEvent

        switch first.event {
        case .LOAD:
            switch second.event {
            case .BEGIN, .AD_BEGIN: break
            default:
                throw EventError.outOfOrder(first, second)
            }
        case .AD_BEGIN:
            if second.event != .AD_COMPLETE { throw EventError.outOfOrder(first, second) }
        case .AD_COMPLETE:
            switch second.event {
            case .BEGIN, .PROGRESS, .AD_BEGIN: break
            default: throw EventError.outOfOrder(first, second)
            }
        case .PROGRESS:
            switch second.event {
            case .PROGRESS, .AD_BEGIN, .COMPLETE: break
            default: throw EventError.outOfOrder(first, second)
            }
        case .COMPLETE: throw EventError.outOfOrder(first, second)
        default: break
        }
    }
    
        public init(userName: String, password: String, debug: Bool = false, verbose: Bool = false) {
    	self.userName = userName
    	self.password = password
    	self.debug = debug
    	self.verbose = verbose
    }
}


extension Data {
    var prettyPrintedJSONString: NSString? { /// NSString gives us a nice sanitized debugDescription
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let prettyPrintedString = NSString(data: data, encoding: String.Encoding.utf8.rawValue) else { return nil }

        return prettyPrintedString
    }
}

