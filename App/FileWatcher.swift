import Foundation

/// Calls `onChange` when the file at `url` is modified, including when an editor saves
/// atomically by replacing the file (which invalidates the old file descriptor).
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File is briefly missing mid-replace; try again shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.start() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                source.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.start()
                    self?.onChange()
                }
            } else {
                self.onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }
}
