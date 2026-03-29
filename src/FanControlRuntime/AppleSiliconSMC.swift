import Foundation

enum AppleSiliconFamily: String {
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case m5 = "M5"
    case a18 = "A18"
}

enum AppleSiliconPlatform {
    static func currentFamily() -> AppleSiliconFamily? {
        guard let model = hardwareModel() else {
            return nil
        }

        return familyByHardwareModel[model]
    }

    private static func hardwareModel() -> String? {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return nil
        }

        let modelBytes = bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        let model = String(decoding: modelBytes, as: UTF8.self)
        return model.isEmpty ? nil : model
    }

    // Apple Silicon model-family mapping adapted from iSMC:
    // https://github.com/dkorunic/iSMC
    private static let familyByHardwareModel: [String: AppleSiliconFamily] = [
        "Macmini9,1": .m1,
        "Mac14,3": .m2,
        "Mac14,12": .m2,
        "Mac16,10": .m4,
        "Mac16,11": .m4,

        "Mac13,1": .m1,
        "Mac13,2": .m1,
        "Mac14,13": .m2,
        "Mac14,14": .m2,
        "Mac15,14": .m3,
        "Mac16,9": .m4,

        "Mac14,8": .m2,

        "iMac21,1": .m1,
        "iMac21,2": .m1,
        "Mac15,4": .m3,
        "Mac15,5": .m3,
        "Mac16,2": .m4,
        "Mac16,3": .m4,

        "Mac17,5": .a18,

        "MacBookAir10,1": .m1,
        "Mac14,2": .m2,
        "Mac14,15": .m2,
        "Mac15,12": .m3,
        "Mac15,13": .m3,
        "Mac16,12": .m4,
        "Mac16,13": .m4,
        "Mac17,3": .m5,
        "Mac17,4": .m5,

        "MacBookPro17,1": .m1,
        "MacBookPro18,1": .m1,
        "MacBookPro18,2": .m1,
        "MacBookPro18,3": .m1,
        "MacBookPro18,4": .m1,
        "Mac14,7": .m2,
        "Mac14,5": .m2,
        "Mac14,6": .m2,
        "Mac14,9": .m2,
        "Mac14,10": .m2,
        "Mac15,3": .m3,
        "Mac15,6": .m3,
        "Mac15,7": .m3,
        "Mac15,8": .m3,
        "Mac15,9": .m3,
        "Mac15,10": .m3,
        "Mac16,1": .m4,
        "Mac16,5": .m4,
        "Mac16,6": .m4,
        "Mac16,7": .m4,
        "Mac16,8": .m4,
        "Mac17,2": .m5,
        "Mac17,6": .m5,
        "Mac17,7": .m5,
        "Mac17,8": .m5,
        "Mac17,9": .m5
    ]
}

enum AppleSiliconSMCReference {
    static func temperatureCandidates(for family: AppleSiliconFamily) -> [SMCSensorCandidate] {
        commonAppleSiliconCandidates + (familyCandidates[family] ?? [])
    }

    private static let commonAppleSiliconCandidates: [SMCSensorCandidate] = [
        .init(key: "TaLP", label: "Airflow Left", group: "Airflow", type: "airflow", minimumUsableValue: 0),
        .init(key: "TaRF", label: "Airflow Right", group: "Airflow", type: "airflow", minimumUsableValue: 0),
        .init(key: "TH0x", label: "NAND", group: "Storage", type: "ssd"),
        .init(key: "TaLT", label: "Thunderbolt Left Proximity", group: "Thermal", type: "io"),
        .init(key: "TaRT", label: "Thunderbolt Right Proximity", group: "Thermal", type: "io")
    ]

    // CPU/GPU Apple Silicon SMC key tables adapted from iSMC:
    // https://github.com/dkorunic/iSMC/blob/master/src/temp.txt
    private static let familyCandidates: [AppleSiliconFamily: [SMCSensorCandidate]] = [
        .m1: [
            .init(key: "Tp09", label: "CPU Efficiency Core 1", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp0T", label: "CPU Efficiency Core 2", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp01", label: "CPU Performance Core 1", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp05", label: "CPU Performance Core 2", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0D", label: "CPU Performance Core 3", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0H", label: "CPU Performance Core 4", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0L", label: "CPU Performance Core 5", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0P", label: "CPU Performance Core 6", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0X", label: "CPU Performance Core 7", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0b", label: "CPU Performance Core 8", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tg05", label: "GPU 1", group: "GPU", type: "gpu"),
            .init(key: "Tg0D", label: "GPU 2", group: "GPU", type: "gpu"),
            .init(key: "Tg0L", label: "GPU 3", group: "GPU", type: "gpu"),
            .init(key: "Tg0T", label: "GPU 4", group: "GPU", type: "gpu")
        ],
        .m2: [
            .init(key: "Tp1h", label: "CPU Efficiency Core 1", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp1t", label: "CPU Efficiency Core 2", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp1p", label: "CPU Efficiency Core 3", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp1l", label: "CPU Efficiency Core 4", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp01", label: "CPU Performance Core 1", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp05", label: "CPU Performance Core 2", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp09", label: "CPU Performance Core 3", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0D", label: "CPU Performance Core 4", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0X", label: "CPU Performance Core 5", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0b", label: "CPU Performance Core 6", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0f", label: "CPU Performance Core 7", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0j", label: "CPU Performance Core 8", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tg0f", label: "GPU 1", group: "GPU", type: "gpu"),
            .init(key: "Tg0j", label: "GPU 2", group: "GPU", type: "gpu")
        ],
        .m3: [
            .init(key: "Te05", label: "CPU Efficiency Core 1", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Te0L", label: "CPU Efficiency Core 2", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Te0P", label: "CPU Efficiency Core 3", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Te0S", label: "CPU Efficiency Core 4", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tf04", label: "CPU Performance Core 1", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf09", label: "CPU Performance Core 2", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf0A", label: "CPU Performance Core 3", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf0B", label: "CPU Performance Core 4", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf0D", label: "CPU Performance Core 5", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf0E", label: "CPU Performance Core 6", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf44", label: "CPU Performance Core 7", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf49", label: "CPU Performance Core 8", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf4A", label: "CPU Performance Core 9", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf4B", label: "CPU Performance Core 10", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf4D", label: "CPU Performance Core 11", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf4E", label: "CPU Performance Core 12", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tf14", label: "GPU 1", group: "GPU", type: "gpu"),
            .init(key: "Tf18", label: "GPU 2", group: "GPU", type: "gpu"),
            .init(key: "Tf19", label: "GPU 3", group: "GPU", type: "gpu"),
            .init(key: "Tf1A", label: "GPU 4", group: "GPU", type: "gpu"),
            .init(key: "Tf24", label: "GPU 5", group: "GPU", type: "gpu"),
            .init(key: "Tf28", label: "GPU 6", group: "GPU", type: "gpu"),
            .init(key: "Tf29", label: "GPU 7", group: "GPU", type: "gpu"),
            .init(key: "Tf2A", label: "GPU 8", group: "GPU", type: "gpu")
        ],
        .m4: [
            .init(key: "Te05", label: "CPU Efficiency Core 1", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Te0S", label: "CPU Efficiency Core 2", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Te09", label: "CPU Efficiency Core 3", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Te0H", label: "CPU Efficiency Core 4", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tp01", label: "CPU Performance Core 1", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp05", label: "CPU Performance Core 2", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp09", label: "CPU Performance Core 3", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0D", label: "CPU Performance Core 4", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0V", label: "CPU Performance Core 5", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0Y", label: "CPU Performance Core 6", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0b", label: "CPU Performance Core 7", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0e", label: "CPU Performance Core 8", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tg0G", label: "GPU 1", group: "GPU", type: "gpu"),
            .init(key: "Tg1U", label: "GPU 1", group: "GPU", type: "gpu"),
            .init(key: "Tg0H", label: "GPU 2", group: "GPU", type: "gpu"),
            .init(key: "Tg1k", label: "GPU 2", group: "GPU", type: "gpu"),
            .init(key: "Tg0K", label: "GPU 3", group: "GPU", type: "gpu"),
            .init(key: "Tg0L", label: "GPU 4", group: "GPU", type: "gpu"),
            .init(key: "Tg0d", label: "GPU 5", group: "GPU", type: "gpu"),
            .init(key: "Tg0e", label: "GPU 6", group: "GPU", type: "gpu"),
            .init(key: "Tg0j", label: "GPU 7", group: "GPU", type: "gpu"),
            .init(key: "Tg0k", label: "GPU 8", group: "GPU", type: "gpu"),
            .init(key: "Tm0p", label: "Memory 1", group: "Memory", type: "memory"),
            .init(key: "Tm1p", label: "Memory 2", group: "Memory", type: "memory"),
            .init(key: "Tm2p", label: "Memory 3", group: "Memory", type: "memory")
        ],
        .m5: [
            .init(key: "Tp00", label: "CPU Super Core 1", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp04", label: "CPU Super Core 2", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp08", label: "CPU Super Core 3", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp0C", label: "CPU Super Core 4", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp0G", label: "CPU Super Core 5", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp0K", label: "CPU Super Core 6", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp0O", label: "CPU Performance Core 1", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0R", label: "CPU Performance Core 2", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0U", label: "CPU Performance Core 3", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0X", label: "CPU Performance Core 4", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0a", label: "CPU Performance Core 5", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0d", label: "CPU Performance Core 6", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0g", label: "CPU Performance Core 7", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0j", label: "CPU Performance Core 8", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0m", label: "CPU Performance Core 9", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0p", label: "CPU Performance Core 10", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0u", label: "CPU Performance Core 11", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp0y", label: "CPU Performance Core 12", group: "CPU Performance Cores Average", type: "cpu-performance"),
            .init(key: "Tp12", label: "CPU Super Core Cluster 1", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp16", label: "CPU Super Core Cluster 2", group: "CPU Super Cores Average", type: "cpu-super"),
            .init(key: "Tp1E", label: "CPU Efficiency Core Cluster", group: "CPU Efficiency Cores Average", type: "cpu-efficiency"),
            .init(key: "Tg0U", label: "GPU 1", group: "GPU", type: "gpu"),
            .init(key: "Tg0X", label: "GPU 2", group: "GPU", type: "gpu"),
            .init(key: "Tg0d", label: "GPU 3", group: "GPU", type: "gpu"),
            .init(key: "Tg0g", label: "GPU 4", group: "GPU", type: "gpu"),
            .init(key: "Tg0j", label: "GPU 5", group: "GPU", type: "gpu"),
            .init(key: "Tg1Y", label: "GPU 6", group: "GPU", type: "gpu"),
            .init(key: "Tg1c", label: "GPU 7", group: "GPU", type: "gpu"),
            .init(key: "Tg1g", label: "GPU 8", group: "GPU", type: "gpu")
        ],
        .a18: []
    ]
}
