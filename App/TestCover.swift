#if DEBUG
import UIKit

/// `-pickTestCover` (Debug builds only): a picture drawn here in code, which *Edit Details* takes
/// in place of a file from the Files picker. Tall like a cover, a jade field under a paler band,
/// so a screenshot shows it plainly.
enum TestCover {
    static var png: Data {
        let size = CGSize(width: 400, height: 580)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor(red: 0.16, green: 0.44, blue: 0.38, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.90, green: 0.95, blue: 0.93, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.14))
        }
    }
}
#endif
