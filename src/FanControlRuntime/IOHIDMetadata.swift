import Foundation

struct IOHIDSensorMetadata {
    let rawName: String
    let friendlyName: String
    let type: String?
    let group: String?
}

enum IOHIDSensorMetadataStore {
    static let shared = load()

    private static func load() -> [String: IOHIDSensorMetadata] {
        guard let url = Bundle.module.url(forResource: "IOKitSensors", withExtension: "xml") else {
            return [:]
        }

        guard let parser = XMLParser(contentsOf: url) else {
            return [:]
        }

        let delegate = IOKitSensorsXMLParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            return [:]
        }
        return delegate.metadataByRawName
    }
}

private final class IOKitSensorsXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var metadataByRawName: [String: IOHIDSensorMetadata] = [:]

    private var currentGroup: String?
    private var currentName: String?
    private var currentType: String?
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        switch elementName {
        case "group":
            currentGroup = attributeDict["name"]
        case "iokit":
            currentName = attributeDict["name"]
            currentType = attributeDict["type"]
            currentText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "iokit":
            guard let currentName else {
                return
            }

            let friendly = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            metadataByRawName[currentName] = IOHIDSensorMetadata(
                rawName: currentName,
                friendlyName: friendly.isEmpty ? currentName : friendly,
                type: currentType,
                group: currentGroup
            )

            self.currentName = nil
            self.currentType = nil
            self.currentText = ""
        case "group":
            currentGroup = nil
        default:
            break
        }
    }
}
