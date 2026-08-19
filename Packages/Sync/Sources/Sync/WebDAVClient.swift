import Foundation

/// 轻量 WebDAV 客户端。只实现本项目需要的操作：
/// PROPFIND（列目录）、GET（下载）、PUT（上传）、MKCOL（建目录）。
/// 认证使用 Basic Auth（Koofr WebDAV 支持）。
public final class WebDAVClient: Sendable {
    public enum WebDAVError: Error, LocalizedError {
        case invalidURL
        case notAuthenticated
        case serverError(statusCode: Int)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL 无效"
            case .notAuthenticated: return "未认证（用户名/密码错误）"
            case .serverError(let code): return "服务器错误（HTTP \(code)）"
            }
        }
    }

    public struct Entry {
        public let name: String
        public let isDirectory: Bool
    }

    private let credentials: WebDAVCredentials
    private let session: URLSession

    public init(credentials: WebDAVCredentials) {
        self.credentials = credentials
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - 基础请求

    private var authHeader: String {
        let data = Data("\(credentials.username):\(credentials.password)".utf8)
        return "Basic \(data.base64EncodedString())"
    }

    private func makeURL(relativePath: String) -> URL? {
        // 拼接根 URL + 相对路径，处理百分号编码（目录名/文件名可能含空格等）。
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = credentials.normalizedBaseURL
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: base + encoded)
    }

    /// 统一请求执行：打 auth 头、区分 data/upload、把非 HTTP 响应、401/403 与
    /// 未通过 `accepted` 的状态码转成 `WebDAVError`。各操作只关心自己的成功条件。
    private func perform(
        _ request: URLRequest,
        uploadData: Data? = nil,
        accepted: (Int) -> Bool
    ) async throws -> Data {
        var request = request
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let result: (Data, URLResponse)
        if let uploadData {
            result = try await session.upload(for: request, from: uploadData)
        } else {
            result = try await session.data(for: request)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw WebDAVError.serverError(statusCode: -1)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WebDAVError.notAuthenticated
        }
        guard accepted(http.statusCode) else {
            throw WebDAVError.serverError(statusCode: http.statusCode)
        }
        return result.0
    }

    // MARK: - 目录列表

    /// 列出 `relativePath`（如 `Rime_Sync/`）下的一级子项。
    public func listDirectory(relativePath: String) async throws -> [Entry] {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = """
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>
        """
        request.httpBody = Data(body.utf8)

        let data = try await perform(request) { (200..<300).contains($0) }
        let basePath = url.path.removingPercentEncoding ?? url.path
        return parseMultiStatus(data: data, basePath: basePath, baseAbsoluteURL: url)
    }

    // MARK: - 下载

    public func download(relativePath: String) async throws -> Data {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        let request = URLRequest(url: url)
        return try await perform(request) { $0 == 200 }
    }

    // MARK: - 上传

    public func upload(relativePath: String, data: Data) async throws {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        _ = try await perform(request, uploadData: data) { (200..<300).contains($0) }
    }

    // MARK: - 建目录

    public func createDirectory(relativePath: String) async throws {
        guard let url = makeURL(relativePath: relativePath) else {
            throw WebDAVError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        // 405 = 已存在，视为成功。
        _ = try await perform(request) { $0 == 201 || $0 == 405 || (200..<300).contains($0) }
    }

    // MARK: - PROPFIND 响应解析

    /// 解析 WebDAV multistatus XML，返回 `relativePath` 下的一级子项。
    /// `basePath` 用于去掉服务器返回的绝对路径前缀，只保留相对名。
    private func parseMultiStatus(data: Data, basePath: String, baseAbsoluteURL: URL) -> [Entry] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        let parser = PROPFINDParser(xml: xml, basePath: basePath, baseAbsoluteURL: baseAbsoluteURL)
        return parser.parse()
    }
}

/// 极简 PROPFIND XML 解析：只认 `<response><href>…</href>…<resourcetype><collection/></resourcetype></response>`。
private final class PROPFINDParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let basePath: String
    private let baseAbsoluteURL: URL

    private var currentHref: String?
    private var isInHref = false
    private var isInResourceType = false
    private var isCollection = false
    private var entries: [WebDAVClient.Entry] = []

    init(xml: String, basePath: String, baseAbsoluteURL: URL) {
        self.parser = XMLParser(data: Data(xml.utf8))
        self.basePath = basePath
        self.baseAbsoluteURL = baseAbsoluteURL
        super.init()
        self.parser.delegate = self
    }

    func parse() -> [WebDAVClient.Entry] {
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch local {
        case "href":
            isInHref = true
            currentHref = ""
        case "resourcetype":
            isInResourceType = true
        case "collection":
            if isInResourceType {
                isCollection = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInHref {
            currentHref = (currentHref ?? "") + string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch local {
        case "href":
            isInHref = false
        case "resourcetype":
            isInResourceType = false
        case "response":
            if let href = currentHref, let name = relativeName(fromHref: href), !name.isEmpty {
                entries.append(WebDAVClient.Entry(name: name, isDirectory: isCollection))
            }
            currentHref = nil
            isCollection = false
        default:
            break
        }
    }

    /// 把服务器返回的 href 转成相对路径。href 可能是绝对 URL、绝对路径、或相对路径。
    private func relativeName(fromHref href: String) -> String? {
        let decoded = href.removingPercentEncoding ?? href
        let stripped = decoded.split(separator: "?").first.map(String.init) ?? decoded
        var path: String
        if let url = URL(string: stripped), url.scheme != nil {
            path = url.path
        } else {
            path = stripped
        }

        // 相对 href：去掉查询串后取最后一段，排除等于集合名自身的条目。
        if !path.hasPrefix("/") {
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !trimmed.isEmpty else { return nil }
            let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
            let baseLast = basePath.split(separator: "/").last.map(String.init) ?? basePath
            return name == baseLast ? nil : name
        }

        // 绝对 path/URL：basePath 补尾斜杠做边界匹配，避免 `Rime_Sync2` 误匹配 `Rime_Sync`。
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard path.hasPrefix(base) else { return nil }
        let relative = String(path.dropFirst(base.count))
        let trimmed = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }
}
