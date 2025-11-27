import Foundation
import CryptoKit

/// 轻量级 S3 客户端，使用 AWS Signature V4 签名
/// 参考 AWSBedrockClient.swift 实现
class AWSS3Client {
    private let accessKeyId: String
    private let secretAccessKey: String
    private let region: String
    
    init(accessKeyId: String, secretAccessKey: String, region: String = "us-east-1") {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.region = region
    }
    
    // MARK: - Public API
    
    /// 列出 S3 桶中的对象
    func listObjects(bucket: String, prefix: String? = nil, maxKeys: Int = 1000) async throws -> [S3Object] {
        var queryItems = [URLQueryItem(name: "list-type", value: "2")]
        if let prefix = prefix {
            queryItems.append(URLQueryItem(name: "prefix", value: prefix))
        }
        queryItems.append(URLQueryItem(name: "max-keys", value: String(maxKeys)))
        
        let data = try await request(method: "GET", bucket: bucket, key: nil, queryItems: queryItems)
        return try parseListObjectsResponse(data)
    }
    
    /// 下载 S3 对象
    func getObject(bucket: String, key: String) async throws -> Data {
        return try await request(method: "GET", bucket: bucket, key: key)
    }
    
    /// 下载 S3 对象到本地文件
    func downloadObject(bucket: String, key: String, to localPath: URL) async throws {
        let data = try await getObject(bucket: bucket, key: key)
        try data.write(to: localPath)
    }
    
    /// 获取对象元数据（HEAD 请求）
    func headObject(bucket: String, key: String) async throws -> S3ObjectMetadata {
        let (_, response) = try await requestWithResponse(method: "HEAD", bucket: bucket, key: key)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error.invalidResponse
        }
        
        let contentLength = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
        let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        
        return S3ObjectMetadata(
            contentLength: contentLength,
            contentType: contentType,
            lastModified: lastModified,
            etag: etag
        )
    }
    
    // MARK: - Private Methods
    
    private func request(method: String, bucket: String, key: String?, queryItems: [URLQueryItem]? = nil, body: Data? = nil) async throws -> Data {
        let (data, _) = try await requestWithResponse(method: method, bucket: bucket, key: key, queryItems: queryItems, body: body)
        return data
    }
    
    private func requestWithResponse(method: String, bucket: String, key: String?, queryItems: [URLQueryItem]? = nil, body: Data? = nil) async throws -> (Data, URLResponse) {
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else {
            throw S3Error.missingCredentials
        }
        
        // 构建 URL
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "\(bucket).s3.\(region).amazonaws.com"
        urlComponents.path = key != nil ? "/\(key!)" : "/"
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw S3Error.invalidRequest
        }
        
        print("📦 [S3] \(method) \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // 设置日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: Date())
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        
        // 签名请求
        signRequest(&request, body: body ?? Data(), date: amzDate, bucket: bucket)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ [S3] Error \(httpResponse.statusCode): \(errorMessage)")
                throw S3Error.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
        }
        
        return (data, response)
    }
    
    private func signRequest(_ request: inout URLRequest, body: Data, date: String, bucket: String) {
        let service = "s3"
        let dateStamp = String(date.prefix(8))
        
        // 规范请求
        let canonicalUri = request.url?.path ?? "/"
        let canonicalQueryString = buildCanonicalQueryString(from: request.url)
        let host = request.url?.host ?? ""
        let payloadHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        
        // S3 需要 x-amz-content-sha256 头
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(date)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        
        let canonicalRequest = "\(request.httpMethod!)\n\(canonicalUri)\n\(canonicalQueryString)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        
        // 待签名字符串
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()
        let stringToSign = "\(algorithm)\n\(date)\n\(credentialScope)\n\(canonicalRequestHash)"
        
        // 计算签名
        let signature = calculateSignature(stringToSign: stringToSign, dateStamp: dateStamp, service: service)
        
        // 授权头
        let authorizationHeader = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
    }

    private func buildCanonicalQueryString(from url: URL?) -> String {
        guard let url = url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            return ""
        }

        return queryItems
            .sorted { $0.name < $1.name }
            .map { item in
                let name = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowedRFC3986) ?? item.name
                let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowedRFC3986) ?? ""
                return "\(name)=\(value)"
            }
            .joined(separator: "&")
    }

    private func calculateSignature(stringToSign: String, dateStamp: String, service: String) -> String {
        let kDate = hmac(key: Data("AWS4\(secretAccessKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        let kSigning = hmac(key: kService, data: Data("aws4_request".utf8))
        let signature = hmac(key: kSigning, data: Data(stringToSign.utf8))
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private func hmac(key: Data, data: Data) -> Data {
        var hmac = HMAC<SHA256>(key: SymmetricKey(data: key))
        hmac.update(data: data)
        return Data(hmac.finalize())
    }

    // MARK: - XML Parsing

    private func parseListObjectsResponse(_ data: Data) throws -> [S3Object] {
        let parser = S3ListObjectsParser(data: data)
        return try parser.parse()
    }
}

// MARK: - CharacterSet Extension

private extension CharacterSet {
    /// RFC 3986 unreserved characters for URL encoding
    static let urlQueryAllowedRFC3986: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}

// MARK: - Data Models

struct S3Object {
    let key: String
    let size: Int64
    let lastModified: String?
    let etag: String?
    let storageClass: String?
}

struct S3ObjectMetadata {
    let contentLength: Int64
    let contentType: String?
    let lastModified: String?
    let etag: String?
}

// MARK: - Errors

enum S3Error: Error, LocalizedError {
    case missingCredentials
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "AWS credentials are missing"
        case .invalidRequest:
            return "Invalid S3 request"
        case .invalidResponse:
            return "Invalid S3 response"
        case .httpError(let code, let message):
            return "S3 HTTP error \(code): \(message)"
        case .parseError(let detail):
            return "S3 response parse error: \(detail)"
        }
    }
}

// MARK: - XML Parser for ListObjects

private class S3ListObjectsParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var objects: [S3Object] = []
    private var currentElement: String = ""
    private var currentText: String = ""

    // Current object being parsed
    private var currentKey: String = ""
    private var currentSize: Int64 = 0
    private var currentLastModified: String?
    private var currentETag: String?
    private var currentStorageClass: String?
    private var inContents: Bool = false

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [S3Object] {
        let parser = XMLParser(data: data)
        parser.delegate = self

        if parser.parse() {
            return objects
        } else if let error = parser.parserError {
            throw S3Error.parseError(error.localizedDescription)
        } else {
            throw S3Error.parseError("Unknown XML parsing error")
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "Contents" {
            inContents = true
            currentKey = ""
            currentSize = 0
            currentLastModified = nil
            currentETag = nil
            currentStorageClass = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if inContents {
            switch elementName {
            case "Key":
                currentKey = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            case "Size":
                currentSize = Int64(currentText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            case "LastModified":
                currentLastModified = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            case "ETag":
                currentETag = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            case "StorageClass":
                currentStorageClass = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            case "Contents":
                objects.append(S3Object(
                    key: currentKey,
                    size: currentSize,
                    lastModified: currentLastModified,
                    etag: currentETag,
                    storageClass: currentStorageClass
                ))
                inContents = false
            default:
                break
            }
        }
        currentText = ""
    }
}
