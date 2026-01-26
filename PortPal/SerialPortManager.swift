import Foundation
import IOKit.serial

enum BaudRate: Int, CaseIterable, Identifiable {
    case br9600 = 9600
    case br19200 = 19200
    case br38400 = 38400
    case br57600 = 57600
    case br115200 = 115200

    var id: Int { self.rawValue }
    var speedValue: speed_t { return Darwin.speed_t(self.rawValue) }
    var displayText: String { String(self.rawValue) }
}

enum Parity: String, CaseIterable, Identifiable {
    case none = "None"
    case even = "Even"
    case odd = "Odd"

    var id: String { self.rawValue }
}

enum DataBits: Int, CaseIterable, Identifiable {
    case seven = 7
    case eight = 8

    var id: Int { self.rawValue }
}

enum StopBits: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2

    var id: Int { self.rawValue }
}

enum LineEnding: String, CaseIterable, Identifiable {
    case cr = "CR"
    case lf = "LF"
    case crlf = "CR+LF"

    var id: String { self.rawValue }

    var stringValue: String {
        switch self {
        case .cr:
            return "\r"
        case .lf:
            return "\n"
        case .crlf:
            return "\r\n"
        }
    }
}


class SerialPortManager: ObservableObject {
    @Published var serialPorts: [String] = []
    @Published var selectedPort: String? = nil
    @Published var connectedPortPath: String? = nil
    @Published var isOpen = false
    @Published var isLiveLogging = false
    
    @Published var baudRate: BaudRate = .br115200
    @Published var parity: Parity = .none
    @Published var dataBits: DataBits = .eight
    @Published var stopBits: StopBits = .one
    @Published var lineEnding: LineEnding = .lf

    var onDataReceived: ((String) -> Void)?

    private var fileDescriptor: Int32 = -1
    private var isReading = false
    private let readQueue = DispatchQueue(label: "serial-read-queue", qos: .background)
    private var readBuffer = Data()
    private var logFileHandle: FileHandle? = nil
    
    private let baudRateKey = "serialBaudRate"
    private let parityKey = "serialParity"
    private let dataBitsKey = "serialDataBits"
    private let stopBitsKey = "serialStopBits"
    private let lineEndingKey = "serialLineEnding"

    init() {
        loadSettings()
    }

    func findSerialPorts() {
        var portIterator: io_iterator_t = 0
        let kernResult = findSerialDevices(portType: kIOSerialBSDAllTypes, portIterator: &portIterator)

        if kernResult == KERN_SUCCESS {
            defer { IOObjectRelease(portIterator) }
            var newPorts: [String] = []
            while case let serialPort = IOIteratorNext(portIterator), serialPort != 0 {
                if let bsdPath = getBSDevicePath(for: serialPort) {
                    newPorts.append(bsdPath)
                }
                IOObjectRelease(serialPort)
            }
            DispatchQueue.main.async {
                self.serialPorts = newPorts

                // Clear selected port if it's no longer available
                if let selectedPort = self.selectedPort, !newPorts.contains(selectedPort) {
                    self.selectedPort = nil
                }
            }
        }
    }

    func openPort(path: String) {
        fileDescriptor = open(path, O_RDWR | O_NOCTTY)
        if fileDescriptor == -1 {
            print("Error opening serial port: \(String(cString: strerror(errno)))")
            DispatchQueue.main.async {
                self.isOpen = false
            }
            return
        }

        var termiosOptions = termios()
        if tcgetattr(fileDescriptor, &termiosOptions) == -1 {
            print("Error getting termios options: \(String(cString: strerror(errno)))")
            closePort()
            return
        }

        // Baud Rate
        cfsetspeed(&termiosOptions, self.baudRate.speedValue)

        // Data Bits
        termiosOptions.c_cflag &= ~tcflag_t(CSIZE)
        switch self.dataBits {
        case .seven:
            termiosOptions.c_cflag |= tcflag_t(CS7)
        case .eight:
            termiosOptions.c_cflag |= tcflag_t(CS8)
        }

        // Parity
        switch self.parity {
        case .none:
            termiosOptions.c_cflag &= ~tcflag_t(PARENB)
        case .even:
            termiosOptions.c_cflag |= tcflag_t(PARENB)
            termiosOptions.c_cflag &= ~tcflag_t(PARODD)
        case .odd:
            termiosOptions.c_cflag |= tcflag_t(PARENB)
            termiosOptions.c_cflag |= tcflag_t(PARODD)
        }

        // Stop Bits
        if self.stopBits == .two {
            termiosOptions.c_cflag |= tcflag_t(CSTOPB)
        } else {
            termiosOptions.c_cflag &= ~tcflag_t(CSTOPB)
        }
        
        termiosOptions.c_cflag &= ~tcflag_t(CRTSCTS)
        termiosOptions.c_cflag |= tcflag_t(CREAD | CLOCAL)

        termiosOptions.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)
        termiosOptions.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        termiosOptions.c_oflag &= ~tcflag_t(OPOST)

        termiosOptions.c_cc.16 = 0 // VMIN
        termiosOptions.c_cc.17 = 10 // VTIME

        if tcsetattr(fileDescriptor, TCSANOW, &termiosOptions) == -1 {
            print("Error setting termios options: \(String(cString: strerror(errno)))")
            closePort()
            return
        }

        print("Serial port opened and configured")
        DispatchQueue.main.async {
            self.isOpen = true
            self.connectedPortPath = path
        }
        startReading()
    }

    func closePort() {
        guard fileDescriptor != -1 else { return }
        stopReading()
        if close(fileDescriptor) == -1 {
            print("Error closing port")
        }
        fileDescriptor = -1
        print("Serial port closed")
        DispatchQueue.main.async {
            self.isOpen = false
            self.connectedPortPath = nil
        }
    }

    private func startReading() {
        isReading = true
        readQueue.async {
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while self.isReading {
                let bytesRead = read(self.fileDescriptor, &buffer, bufferSize)

                if bytesRead > 0 {
                    self.readBuffer.append(buffer, count: bytesRead)
                    while let range = self.readBuffer.range(of: Data([0x0A])) { // Newline character
                        let lineData = self.readBuffer.subdata(in: 0..<range.upperBound)
                        self.readBuffer.removeSubrange(0..<range.upperBound)

                        if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .newlines) {
                            DispatchQueue.main.async {
                                self.onDataReceived?(line)
                            }
                            if self.isLiveLogging {
                                let logLine = "[\(Date().ISO8601Format())] \(line)\n"
                                self.writeToLogFile(logLine)
                            }
                        }
                    }
                } else if bytesRead == -1 && errno != EAGAIN {
                    print("Error reading from serial port: \(String(cString: strerror(errno)))")
                    self.isReading = false
                    DispatchQueue.main.async {
                        self.closePort()
                    }
                } else {
                    usleep(10000) // 10ms
                }
            }
        }
    }
    
    func startLiveLogging(fileURL: URL) {
        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            }
            logFileHandle = try FileHandle(forWritingTo: fileURL)
            logFileHandle?.seekToEndOfFile()
            DispatchQueue.main.async { self.isLiveLogging = true }
            print("Started live logging to \(fileURL.path)")
        } catch {
            print("Error starting live logging: \(error.localizedDescription)")
            DispatchQueue.main.async { self.isLiveLogging = false }
        }
    }

    func stopLiveLogging() {
        do {
            try logFileHandle?.close()
            logFileHandle = nil
            DispatchQueue.main.async { self.isLiveLogging = false }
            print("Stopped live logging.")
        } catch {
            print("Error stopping live logging: \(error.localizedDescription)")
        }
    }

    private func writeToLogFile(_ line: String) {
        if let data = line.data(using: .utf8) {
            do {
                try logFileHandle?.write(contentsOf: data)
            } catch {
                print("Error writing to log file: \(error.localizedDescription)")
            }
        }
    }

    func send(_ string: String) {
        guard fileDescriptor != -1 else { return }

        let data = Data(string.utf8)
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
            guard let baseAddress = bytes.baseAddress else { return }
            let rawPointer = UnsafeRawPointer(baseAddress)
            let bytesWritten = write(fileDescriptor, rawPointer, data.count)
            if bytesWritten == -1 {
                print("Error writing to serial port: \(String(cString: strerror(errno)))")
            }
        }
    }

    private func stopReading() {
        isReading = false
    }

    private func findSerialDevices(portType: String, portIterator: inout io_iterator_t) -> kern_return_t {
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchingDict[kIOSerialBSDTypeKey] = portType
        return IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &portIterator)
    }

    private func getBSDevicePath(for service: io_object_t) -> String? {
        let key = kIOCalloutDeviceKey as CFString
        return IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0).takeRetainedValue() as? String
    }
    
    func loadSettings() {
        if let savedBaudRate = UserDefaults.standard.value(forKey: baudRateKey) as? Int {
            self.baudRate = BaudRate(rawValue: savedBaudRate) ?? .br115200
        }
        if let savedParity = UserDefaults.standard.string(forKey: parityKey) {
            self.parity = Parity(rawValue: savedParity) ?? .none
        }
        if let savedDataBits = UserDefaults.standard.value(forKey: dataBitsKey) as? Int {
            self.dataBits = DataBits(rawValue: savedDataBits) ?? .eight
        }
        if let savedStopBits = UserDefaults.standard.value(forKey: stopBitsKey) as? Int {
            self.stopBits = StopBits(rawValue: savedStopBits) ?? .one
        }
        if let savedLineEnding = UserDefaults.standard.string(forKey: lineEndingKey) {
            self.lineEnding = LineEnding(rawValue: savedLineEnding) ?? .lf
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(baudRate.rawValue, forKey: baudRateKey)
        UserDefaults.standard.set(parity.rawValue, forKey: parityKey)
        UserDefaults.standard.set(dataBits.rawValue, forKey: dataBitsKey)
        UserDefaults.standard.set(stopBits.rawValue, forKey: stopBitsKey)
        UserDefaults.standard.set(lineEnding.rawValue, forKey: lineEndingKey)
    }
}

