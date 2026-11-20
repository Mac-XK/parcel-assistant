import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum Barcode {
    static func code128(_ text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(text.utf8)
        filter.quietSpace = 6
        guard let out = filter.outputImage else { return nil }
        let scale = 3.0
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct BarcodeView: View {
    var text: String
    var tint: Color = .black

    var body: some View {
        Group {
            if let img = Barcode.code128(text) {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2))
            }
        }
    }
}
