import SDMEngineBridge

public enum SDMCoreInfo: Sendable {
    public static let engineABIVersion = UInt32(sdm_engine_abi_version())

    public static var engineVersion: String {
        guard let version = sdm_engine_version() else {
            return "unknown"
        }

        return String(cString: version)
    }
}
