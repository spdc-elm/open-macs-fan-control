import Foundation

do {
    let command = try CLI(arguments: CommandLine.arguments).parse()
    try command.run()
} catch let error as CLIError {
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(error.exitCode)
} catch {
    FileHandle.standardError.write(Data(("error: \(error.localizedDescription)\n").utf8))
    exit(1)
}
