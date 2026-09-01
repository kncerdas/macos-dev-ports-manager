import Foundation

/// One row of the system process table, as reported by `ps`.
struct ProcessNode: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let pgid: Int32
    let user: String
    /// Absolute path of the executable (`ps -o comm=`).
    let executablePath: String
    /// Full argument vector (`ps -o command=`). Frequently rewritten by runtimes
    /// such as Node, which is why the ancestor walk exists.
    let command: String

    var id: Int32 { pid }

    var executableName: String {
        (executablePath as NSString).lastPathComponent
    }
}

/// Indexed snapshot of the process table with parent/child navigation.
struct ProcessTable {
    private(set) var nodes: [Int32: ProcessNode] = [:]
    private var childrenByParent: [Int32: [Int32]] = [:]

    static let empty = ProcessTable()

    init(nodes: [ProcessNode] = []) {
        for node in nodes {
            self.nodes[node.pid] = node
            childrenByParent[node.ppid, default: []].append(node.pid)
        }
    }

    subscript(pid: Int32) -> ProcessNode? { nodes[pid] }

    func parent(of pid: Int32) -> ProcessNode? {
        guard let node = nodes[pid], node.ppid > 1 else { return nil }
        return nodes[node.ppid]
    }

    func children(of pid: Int32) -> [ProcessNode] {
        (childrenByParent[pid] ?? []).compactMap { nodes[$0] }
    }

    /// `pid` plus every descendant, parents before children.
    func tree(rootedAt pid: Int32) -> [ProcessNode] {
        guard let root = nodes[pid] else { return [] }
        var result: [ProcessNode] = [root]
        var queue: [Int32] = [pid]
        var seen: Set<Int32> = [pid]
        while let current = queue.first {
            queue.removeFirst()
            for child in children(of: current) where !seen.contains(child.pid) {
                seen.insert(child.pid)
                result.append(child)
                queue.append(child.pid)
            }
        }
        return result
    }

    /// Depth of `pid` below `root`, for indenting the stop-confirmation tree.
    func depth(of pid: Int32, below root: Int32) -> Int {
        var depth = 0
        var current = pid
        while current != root, let node = nodes[current], node.ppid > 1, depth < 16 {
            current = node.ppid
            depth += 1
        }
        return current == root ? depth : 0
    }
}
