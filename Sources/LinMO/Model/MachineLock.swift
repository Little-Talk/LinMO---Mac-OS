import Darwin
import Foundation

final class MachineLock {
    private let descriptor: Int32

    init(url: URL) throws {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            throw LinMOError.message(tr("เปิดไฟล์ล็อกของเครื่องไม่สำเร็จ: \(String(cString: strerror(errno)))", "Could not open the machine lock file: \(String(cString: strerror(errno)))"))
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK {
                throw LinMOError.message(tr("เครื่องนี้กำลังถูกใช้อยู่ในแอพ LinMO อีกตัวหนึ่ง (อาจเป็นแอพที่ build ไว้คนละที่) ปิดเครื่องหรือปิดแอพตัวนั้นก่อน ถ้าเปิดเครื่องเดียวกันซ้อนกันสองที่ ดิสก์ Linux จะเสีย", "This machine is in use by another copy of LinMO (maybe one built in a different place). Shut down the machine or quit that copy first. Running the same machine twice at once corrupts the Linux disk."))
            }
            throw LinMOError.message(tr("ล็อกเครื่องไม่สำเร็จ: \(String(cString: strerror(code)))", "Could not lock the machine: \(String(cString: strerror(code)))"))
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
