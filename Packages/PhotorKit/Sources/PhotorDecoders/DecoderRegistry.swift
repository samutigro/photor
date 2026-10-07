import PhotorCore

public struct DecoderRegistry: PhotoDecoder {
    private let images = ImageIODecoder()
    private let raw = RAWDecoder()
    public init() {}
    public func decode(_ request: DecodeRequest) throws -> DecodedImage {
        try request.asset.isRAW ? raw.decode(request) : images.decode(request)
    }
}
