//
//  CPBitmapHandler.swift
//  Amfeta-Board
//

import UIKit

class CPBitmapHandler {
    static func resizeAndSave(image: UIImage, to url: URL, size: CGSize) throws {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: CGPoint.zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        try? FileManager.default.removeItem(at: url)

        resizedImage.writeToCPBitmapFile(to: url.path as NSString)
    }
}

extension UIImage {
    func writeToCPBitmapFile(to path: NSString) {
        let sel1 = Selector(("_writeToCPBitmapFile:flags:"))
        let sel2 = Selector(("writeToCPBitmapFile:flags:"))
        if self.responds(to: sel1) {
            typealias Func = @convention(c) (AnyObject, Selector, NSString, Int) -> Bool
            let imp = self.method(for: sel1)
            let fn = unsafeBitCast(imp, to: Func.self)
            _ = fn(self, sel1, path, 1)
        } else if self.responds(to: sel2) {
            typealias Func = @convention(c) (AnyObject, Selector, NSString, Int) -> Bool
            let imp = self.method(for: sel2)
            let fn = unsafeBitCast(imp, to: Func.self)
            _ = fn(self, sel2, path, 1)
        }
    }
}
