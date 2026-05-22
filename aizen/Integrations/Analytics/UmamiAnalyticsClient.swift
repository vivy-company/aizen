//
//  UmamiAnalyticsClient.swift
//  aizen
//
//  Umami tracker integration. All direct swift-umami usage stays in this file.
//

import Foundation
import os.log
import Umami

actor UmamiAnalyticsClient {
    private let logger = Logger.forCategory("Analytics")
    private var tracker: UmamiTrackerClient?
    private var trackerBaseURL: URL?
    private var trackerUserAgent: String?

    func track(_ event: AnalyticsEvent, context: AnalyticsContextSnapshot) async {
        guard context.isEnabled, context.isConfigured else { return }
        guard let baseURL = URL(string: context.baseURLString) else { return }

        do {
            let tracker = tracker(for: baseURL, userAgent: context.userAgent)
            _ = try await tracker.track(
                TrackEventRequest(
                    source: .website(context.websiteId),
                    data: mergedProperties(for: event, context: context),
                    hostname: context.hostname,
                    language: context.language,
                    title: context.title,
                    url: event.url,
                    name: event.name,
                    userAgent: context.userAgent,
                    id: context.installId,
                    os: context.osName,
                    device: context.device
                )
            )
        } catch {
            logger.debug("Analytics event \(event.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func tracker(for baseURL: URL, userAgent: String) -> UmamiTrackerClient {
        if let tracker,
           trackerBaseURL == baseURL,
           trackerUserAgent == userAgent {
            return tracker
        }

        let created = UmamiTrackerClient(
            configuration: UmamiConfiguration(
                baseURL: baseURL,
                userAgent: userAgent
            )
        )
        tracker = created
        trackerBaseURL = baseURL
        trackerUserAgent = userAgent
        return created
    }

    private func mergedProperties(
        for event: AnalyticsEvent,
        context: AnalyticsContextSnapshot
    ) -> [String: JSONValue] {
        var properties = context.globalProperties
        for (key, value) in event.properties {
            properties[key] = value
        }
        return properties.mapValues { $0.jsonValue }
    }
}

private extension AnalyticsPropertyValue {
    nonisolated var jsonValue: JSONValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .integer(value)
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            return .number(value)
        }
    }
}
