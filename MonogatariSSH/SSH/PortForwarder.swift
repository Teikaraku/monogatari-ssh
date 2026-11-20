import Foundation
import Citadel
import NIOCore
import NIOPosix
import NIOSSH

/// 本地端口转发：127.0.0.1:localPort → (经 SSH) → remoteHost:remotePort
final class PortForwarder {
    let client: SSHClient
    let rule: PortForward
    private var server: Channel?

    init(client: SSHClient, rule: PortForward) {
        self.client = client
        self.rule = rule
    }

    func start() async throws {
        let client = self.client
        let rule = self.rule
        let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { local in
                let promise = local.eventLoop.makePromise(of: Void.self)
                Task {
                    do {
                        let origin = try SocketAddress(ipAddress: "127.0.0.1", port: rule.localPort)
                        let localGlue = GlueHandler()
                        let remote = try await client.createDirectTCPIPChannel(
                            using: SSHChannelType.DirectTCPIP(targetHost: rule.remoteHost,
                                                              targetPort: rule.remotePort,
                                                              originatorAddress: origin)
                        ) { remote in
                            let remoteGlue = GlueHandler()
                            GlueHandler.pair(localGlue, remoteGlue)
                            return remote.pipeline.addHandler(remoteGlue)
                        }
                        _ = remote
                        try await local.pipeline.addHandler(localGlue).get()
                        local.setOption(ChannelOptions.autoRead, value: true).whenComplete { _ in }
                        local.read()
                        promise.succeed(())
                    } catch {
                        local.close(promise: nil)
                        promise.fail(error)
                    }
                }
                return promise.futureResult
            }
        server = try await bootstrap.bind(host: "127.0.0.1", port: rule.localPort).get()
    }

    func stop() {
        server?.close(promise: nil)
        server = nil
    }
}

/// 两个 Channel 之间双向搬运 ByteBuffer（参考 swift-nio 示例的 GlueHandler）。
final class GlueHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var partner: GlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    static func pair(_ a: GlueHandler, _ b: GlueHandler) {
        a.partner = b
        b.partner = a
    }

    func handlerAdded(context: ChannelHandlerContext) { self.context = context }
    func handlerRemoved(context: ChannelHandlerContext) { self.context = nil; partner = nil }

    private func partnerWrite(_ data: NIOAny) {
        guard let ctx = context else { return }
        ctx.eventLoop.execute { ctx.writeAndFlush(data, promise: nil) }
    }
    private func partnerCloseFull() {
        guard let ctx = context else { return }
        ctx.eventLoop.execute { ctx.close(promise: nil) }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.partnerWrite(data)
    }
    func channelInactive(context: ChannelHandlerContext) {
        partner?.partnerCloseFull()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
    func read(context: ChannelHandlerContext) {
        context.read()
    }
}
