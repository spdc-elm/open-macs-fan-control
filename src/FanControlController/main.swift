import Foundation
import FanControlRuntime

do {
    try AutomaticControlControllerServer().run()
} catch {
    FileHandle.standardError.write(Data(("error: \(error.localizedDescription)\n").utf8))
    exit(1)
}
