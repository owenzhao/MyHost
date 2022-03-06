#if os(macOS)
import Cocoa
#else
import UIKit
#endif

//import Reachability
import Network

public class MyHost {
    let monitor = NWPathMonitor()
    var reachable = true
    
    private var enthernet = NetworkLink(MAC: "") {
        didSet {
            if enthernet != oldValue {
                NotificationCenter.default.post(name: MyHost.EnthernetUpdate, object: enthernet)
            }
        }
    }
    private var wifi = NetworkLink(MAC: "") {
        didSet {
            if wifi != oldValue {
                DispatchQueue.main.async { [self] in
                    NotificationCenter.default.post(name: MyHost.WifiUpdate, object: wifi)
                }
            }
        }
    }
    private var internetIPV4 = "" {
        didSet {
            if internetIPV4 != oldValue {
                DispatchQueue.main.async { [self] in
                    NotificationCenter.default.post(name: MyHost.InternetIPV4Update, object: internetIPV4)
                }
            }
        }
    }
    private var internetIPV6 = "" {
        didSet {
            if internetIPV6 != oldValue {
                DispatchQueue.main.async { [self] in
                    NotificationCenter.default.post(name: MyHost.InternetIPV4Update, object: internetIPV6)
                }
            }
        }
    }

    public init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    print("REACHABLE!")
                    self.reachable = true
                } else {
                    self.reachable = false
                    print("UNREACHABLE!")
                }
            }
        }
        
        monitor.start(queue: .global(qos: .background))
        
        getLocalIPAndMACAdress()
        
        Task {
            await getInternetIP()
            await observeIPChange()
        }
    }
}

extension MyHost {
    public static let EnthernetUpdate = Notification.Name("EnthernetUpdate")
    public static let WifiUpdate = Notification.Name("WifiUpdate")
    public static let InternetIPV4Update = Notification.Name("InternetIPV4Update")
    public static let InternetIPV6Update = Notification.Name("InternetIPV6Update")
    
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
            
            networkLinkDictionary.keys.sorted().forEach { key in
                print(key, "\t", networkLinkDictionary[key]!)
            }
        }
    }
    
    private func set(networkLinkDictionary:[String:[String]]) {
        networkLinkDictionary.keys.sorted().forEach {
            switch $0 {
                // for iMac 5K, en0 is ethernet; en1 is WiFi
            case "en0":
                enthernet = getNetworkLink(values: networkLinkDictionary["en0"] ?? [])
                print(enthernet)
            case "en1":
                wifi = getNetworkLink(values: networkLinkDictionary["en1"] ?? [])
                print(wifi)
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
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                Task {
                    await observeIPChange()
                }
            }
        }
        
        IPType.allCases.forEach { type in
            Task {
                await setInterIP(type:type)
            }
        }
    }
    
    private func setInterIP(type:IPType) async {
        let url:URL
        
        if !reachable {
            switch type {
            case .ipv4:
                internetIPV4 = NSLocalizedString("Inactive", bundle: .module, comment: "")
            case .ipv6:
                internetIPV6 = NSLocalizedString("Inactive", bundle: .module, comment: "")
            }
            
            return
        }
        
        switch type {
        case .ipv4:
            url = URL(string: "https://api.ipify.org?format=json")!
        case .ipv6:
            url = URL(string: "https://api64.ipify.org?format=json")!
        }
        let urlSessionConfiguration = URLSessionConfiguration.default
        let urlSession = URLSession(configuration: urlSessionConfiguration)
        
        do {
            let (data, urlResponse) = try await urlSession.data(from: url)
            DispatchQueue.main.async { [self] in
                if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let dic = try? JSONSerialization.jsonObject(with: data, options: []) as? [String:String] {
                        switch type {
                        case .ipv4:
                            internetIPV4 = dic["ip"]!
                            print(internetIPV4)
                        case .ipv6:
                            internetIPV6 = dic["ip"]!
                            print(internetIPV6)
                        }
                    }
                } else {
                    print(urlResponse)
                }
            }
        } catch {
            print(error)
        }
    }
}

public struct NetworkLink:Equatable {
    public init(MAC:String, ipv6:String?, ipv4:String?){
        self.MAC = MAC
        self.ipv6 = ipv6
        self.ipv4 = ipv4
    }
    
    public let MAC:String
    public var ipv6:String? = nil
    public var ipv4:String? = nil
}

enum IPType: CaseIterable {
    case ipv4
    case ipv6
}
