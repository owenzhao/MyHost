#if os(macOS)
import Cocoa
#else
import UIKit
#endif

//import Reachability
import Network
import SpeedTestServiceNotification

public class MyHost:ObservableObject {
    let monitor = NWPathMonitor()
    public private(set) var shouldStop = false {
        didSet {
            if shouldStop {
                state = "stopped"
            } else {
                state = "running"
            }
        }
    }
    
    @Published public var state:String = "not running"
    
    @Published public var reachable = false {
        didSet {
            if reachable != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: MyHost.ReachableUpdate, object: self.reachable)
                }
            }
        }
    }
    
    @Published public var enthernet = NetworkLink(MAC: "") {
        didSet {
            if enthernet != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: MyHost.EnthernetUpdate, object: self.enthernet)
                }
            }
        }
    }
    @Published public var wifi = NetworkLink(MAC: "") {
        didSet {
            if wifi != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: MyHost.WifiUpdate, object: self.wifi)
                }
            }
        }
    }
    @Published public var internetIPV4 = "" {
        didSet {
            if internetIPV4 != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: MyHost.InternetIPV4Update, object: self.internetIPV4)
                }
            }
        }
    }
    @Published public var internetIPV6 = "" {
        didSet {
            if internetIPV6 != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: MyHost.InternetIPV6Update, object: self.internetIPV6)
                }
            }
        }
    }

    public func updateHostNotifications() {
        DispatchQueue.main.async { [self] in
            NotificationCenter.default.post(name: MyHost.EnthernetUpdate, object: enthernet)
            NotificationCenter.default.post(name: MyHost.WifiUpdate, object: wifi)
            NotificationCenter.default.post(name: MyHost.InternetIPV4Update, object: internetIPV4)
            NotificationCenter.default.post(name: MyHost.InternetIPV6Update, object: internetIPV6)
        }
    }
    
    public func start() async {
        DispatchQueue.main.async {
            self.state = "running"
            
            if self.shouldStop {
                self.shouldStop = false
            }
        }
        
        getLocalIPAndMACAdress()
        await getInternetIP()
    }
    
    public func stop() {
        DispatchQueue.main.async {
            self.shouldStop = true
        }
    }
    
    static public var shared = MyHost()

    private init() {
        NotificationCenter.default.addObserver(forName: SpeedTestServiceNotification.stop, object: nil, queue: nil) { _ in
            self.shouldStop = true
        }
        
        monitor.pathUpdateHandler = { [self] path in
            if path.status == .satisfied {
                #if DEBUG
                debugPrint("REACHABLE!")
                #endif
                DispatchQueue.main.async {
                    self.reachable = true
                }
            } else {
                DispatchQueue.main.async {
                    self.reachable = false
                }
                #if DEBUG
                debugPrint("UNREACHABLE!")
                #endif
            }
        }
        
        monitor.start(queue: .global(qos: .background))
    }
}

extension MyHost {
    public static let ReachableUpdate = Notification.Name("ReachableUpdate")
    public static let EnthernetUpdate = Notification.Name("EnthernetUpdate")
    public static let WifiUpdate = Notification.Name("WifiUpdate")
    public static let InternetIPV4Update = Notification.Name("InternetIPV4Update")
    public static let InternetIPV6Update = Notification.Name("InternetIPV6Update")
    
    public static let inactivceString = NSLocalizedString("Inactive", bundle: .module, comment: "")
    
    private func getLocalIPAndMACAdress() {
        var address : String?

        // Get list of all interfaces on the local machine:
        var ifaddr:UnsafeMutablePointer<ifaddrs>!
        if getifaddrs(&ifaddr) == 0 {
            // For each interface ...
            var ptr:UnsafeMutablePointer<ifaddrs>! = ifaddr
            var networkLinkDictionary = [String:[String]]()
            
            repeat {
                defer { ptr = ptr.pointee.ifa_next}
                let interface = ptr.pointee
                // Check interface name:
                let name = String(cString: interface.ifa_name)
                // Convert interface address to a human readable string:
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                address = String(cString: hostname)
                var values = networkLinkDictionary[name] ?? []
                values.append(address!)
                networkLinkDictionary.updateValue(values, forKey: name)
            } while ptr != nil
       
            freeifaddrs(ifaddr)
            
            set(networkLinkDictionary: networkLinkDictionary)
            
            #if DEBUG
            networkLinkDictionary.keys.sorted().forEach { key in
                print(key, "\t", networkLinkDictionary[key]!)
            }
            #endif
        }
    }
    
    private func set(networkLinkDictionary:[String:[String]]) {
        networkLinkDictionary.keys.sorted().forEach {
            switch $0 {
                // for iMac 5K, en0 is ethernet; en1 is WiFi
            case "en0":
                DispatchQueue.main.async { [self] in
                    enthernet = getNetworkLink(values: networkLinkDictionary["en0"] ?? [])
                }
                #if DEBUG
                debugPrint(enthernet)
                #endif
            case "en1":
                DispatchQueue.main.async { [self] in
                    wifi = getNetworkLink(values: networkLinkDictionary["en1"] ?? [])
                }
                #if DEBUG
                debugPrint(wifi)
                #endif
            default:
                break
            }
        }
    }
    
    private func getNetworkLink(values:[String]) -> NetworkLink {
        let networkLink:NetworkLink
        
        switch values.count {
        case 1:
            networkLink = NetworkLink(MAC: values[0])
        case 2:
            networkLink = NetworkLink(MAC: values[0], ipv6: values[1])
        case 3:
            networkLink = NetworkLink(MAC: values[0], ipv6: values[1], ipv4: values[2])
        default:
            networkLink = NetworkLink(MAC: "")
        }
        
        return networkLink
    }
    
    private func observeIPChange() async {
        getLocalIPAndMACAdress()
        
        await getInternetIP()
    }
    
    private func getInternetIP() async {
        for type in IPType.allCases {
            await setInterIP(type: type)
        }
        
        try! await Task.sleep(nanoseconds: 1000_000_000 * 5)
        
        if !shouldStop {
            await observeIPChange()
        }
    }
    
    private func setInterIP(type:IPType) async { 
        let url:URL
        
        if !reachable {
            switch type {
            case .ipv4:
                internetIPV4 = MyHost.inactivceString
            case .ipv6:
                internetIPV6 = MyHost.inactivceString
            }
            
            return
        }
        
        switch type {
        case .ipv4:
            url = URL(string: "https://api.ipify.org?format=json")!
            
            if internetIPV4.isEmpty {
                DispatchQueue.main.async {
                    self.internetIPV4 = "..."
                }
            }
        case .ipv6:
            url = URL(string: "https://api64.ipify.org?format=json")!
            
            if internetIPV6.isEmpty {
                DispatchQueue.main.async {
                    self.internetIPV6 = "..."
                }
            }
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSession = URLSession(configuration: urlSessionConfiguration)
        
        do {
            let (data, urlResponse) = try await urlSession.data(from: url)
            if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let dic = try? JSONSerialization.jsonObject(with: data, options: []) as? [String:String] {
                    switch type {
                    case .ipv4:
                        DispatchQueue.main.async {
                            self.internetIPV4 = dic["ip"]!
                        }
                        #if DEBUG
                        debugPrint(internetIPV4)
                        #endif
                    case .ipv6:
                        DispatchQueue.main.async {
                            self.internetIPV6 = dic["ip"]!
                        }
                        #if DEBUG
                        debugPrint(internetIPV6)
                        #endif
                    }
                }
            } else {
                #if DEBUG
                debugPrint(urlResponse)
                #endif
            }
        } catch {
            print(error)
        }
    }
}

public struct NetworkLink:Equatable {
    public init(MAC:String, ipv6:String? = nil, ipv4:String? = nil){
        self.MAC = MAC
        self.ipv6 = ipv6
        self.ipv4 = ipv4
    }
    
    public let MAC:String
    public var ipv6:String? = nil
    public var ipv4:String? = nil
}

public enum IPType: CaseIterable {
    case ipv4
    case ipv6
}
