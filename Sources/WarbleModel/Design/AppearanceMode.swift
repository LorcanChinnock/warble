import Foundation

/// Whether Warble's windows follow the system appearance or keep to light or dark, from Settings › General.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark
}
