import Foundation
import CryptoKit

class AWSBedrockClient {
    private let accessKeyId: String
    private let secretAccessKey: String
    private let region: String
    private let model = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

    init(accessKeyId: String, secretAccessKey: String, region: String = "us-east-1") {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.region = region
    }
    
    func invokeText(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("🤖 [DEBUG] Starting AWS Bedrock text query...")

        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else {
            completion(.failure(AWSError.missingCredentials))
            return
        }

        // 构建请求体（Bedrock 使用 Anthropic Messages API 格式）
        let requestBody: [String: Any] = [
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        invokeModel(requestBody: requestBody, completion: completion)
    }

    func analyzeImage(imageData: Data, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("🤖 [DEBUG] Starting AWS Bedrock image analysis...")

        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty else {
            completion(.failure(AWSError.missingCredentials))
            return
        }

        // 将图片转换为 base64
        let base64Image = imageData.base64EncodedString()
        print("🤖 [DEBUG] Image size: \(imageData.count) bytes, base64 length: \(base64Image.count)")

        // 构建请求体（Bedrock 使用 Anthropic Messages API 格式）
        let requestBody: [String: Any] = [
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        invokeModel(requestBody: requestBody, completion: completion)
    }

    private func invokeModel(requestBody: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(.failure(AWSError.invalidRequest))
            return
        }

        // AWS Bedrock endpoint
        let endpoint = "https://bedrock-runtime.\(region).amazonaws.com/model/\(model)/invoke"
        guard let url = URL(string: endpoint) else {
            completion(.failure(AWSError.invalidRequest))
            return
        }

        print("🤖 [DEBUG] Bedrock endpoint: \(endpoint)")

        // 创建签名请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // AWS Signature V4
        // 生成 ISO8601 基本格式的日期时间: 20251125T124650Z
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        let amzDate = dateFormatter.string(from: now)

        print("🤖 [DEBUG] X-Amz-Date: \(amzDate)")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")

        // 签名请求
        signRequest(&request, body: jsonData, date: amzDate)

        print("🤖 [DEBUG] Sending request to Bedrock...")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ [DEBUG] Request error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                print("❌ [DEBUG] No data received")
                completion(.failure(AWSError.noData))
                return
            }

            // 打印响应用于调试
            if let responseString = String(data: data, encoding: .utf8) {
                print("🤖 [DEBUG] Response: \(responseString.prefix(500))...")
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    print("✅ [DEBUG] Successfully extracted text")
                    print("📝 [DEBUG] Extracted text preview: \(text.prefix(200))...")
                    completion(.success(text))
                } else {
                    print("❌ [DEBUG] Invalid response format")
                    completion(.failure(AWSError.invalidResponse))
                }
            } catch {
                print("❌ [DEBUG] JSON parsing error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func signRequest(_ request: inout URLRequest, body: Data, date: String) {
        // AWS Signature V4 签名过程
        let service = "bedrock"
        let dateStamp = String(date.prefix(8))

        print("🔐 [DEBUG] Signing request...")
        print("🔐 [DEBUG] Date: \(date)")
        print("🔐 [DEBUG] DateStamp: \(dateStamp)")

        // 创建规范请求
        // AWS 要求使用 URL 编码的路径（: 编码为 %3A）
        let rawPath = request.url?.path ?? "/"
        let canonicalUri = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: ":", with: "%3A") ?? rawPath

        let canonicalQueryString = ""
        let host = request.url?.host ?? ""
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-amz-date:\(date)\n"
        let signedHeaders = "content-type;host;x-amz-date"
        let payloadHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()

        let canonicalRequest = "\(request.httpMethod!)\n\(canonicalUri)\n\(canonicalQueryString)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"

        print("🔐 [DEBUG] Raw Path: \(rawPath)")
        print("🔐 [DEBUG] Canonical URI: \(canonicalUri)")
        print("🔐 [DEBUG] Host: \(host)")
        print("🔐 [DEBUG] Payload Hash: \(payloadHash.prefix(32))...")

        // 创建待签名字符串
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()
        let stringToSign = "\(algorithm)\n\(date)\n\(credentialScope)\n\(canonicalRequestHash)"

        print("🔐 [DEBUG] Canonical Request Hash: \(canonicalRequestHash.prefix(32))...")

        // 计算签名
        let signature = calculateSignature(stringToSign: stringToSign, dateStamp: dateStamp, service: service)

        print("🔐 [DEBUG] Signature: \(signature.prefix(16))...")

        // 添加授权头
        let authorizationHeader = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        print("🔐 [DEBUG] Authorization header set")
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
}

enum AWSError: Error, LocalizedError {
    case missingCredentials
    case invalidRequest
    case noData
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "AWS credentials are missing"
        case .invalidRequest:
            return "Invalid request"
        case .noData:
            return "No data received"
        case .invalidResponse:
            return "Invalid response format"
        }
    }
}

