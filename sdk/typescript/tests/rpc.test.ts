import { describe, it, expect, vi, afterEach } from "vitest";
import { Readable } from "stream";
import { RpcTransport } from "../src/rpc.js";

/**
 * Creates a RpcTransport with a mock stdin (pushable Readable)
 * and spied stdout to capture output.
 */
function createMockTransport() {
  const input = new Readable({ read() {} });

  // Replace process.stdin for the constructor's readline
  const origStdin = process.stdin;
  Object.defineProperty(process, "stdin", { value: input, writable: true });
  const transport = new RpcTransport();
  Object.defineProperty(process, "stdin", {
    value: origStdin,
    writable: true,
  });

  // Spy on process.stdout.write to capture outgoing messages
  const writtenChunks: string[] = [];
  const writeSpy = vi
    .spyOn(process.stdout, "write")
    .mockImplementation((chunk: any) => {
      writtenChunks.push(typeof chunk === "string" ? chunk : chunk.toString());
      return true;
    });

  return {
    transport,
    /** Simulate a line from the host arriving on stdin */
    sendToPlugin(message: object) {
      input.push(JSON.stringify(message) + "\n");
    },
    /** Get all JSON messages written to stdout */
    getOutputMessages(): object[] {
      return writtenChunks
        .join("")
        .split("\n")
        .filter((l) => l.trim())
        .map((l) => JSON.parse(l));
    },
    /** Cleanup spy */
    cleanup() {
      writeSpy.mockRestore();
    },
  };
}

describe("RpcTransport", () => {
  let cleanup: () => void;

  afterEach(() => {
    cleanup?.();
  });

  it("sends a request with incrementing ids", () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.transport.request("sandbox/list").catch(() => {});
    mock.transport.request("sandbox/stop", { name: "test" }).catch(() => {});

    const msgs = mock.getOutputMessages();
    expect(msgs).toHaveLength(2);
    expect(msgs[0]).toMatchObject({
      jsonrpc: "2.0",
      id: 1,
      method: "sandbox/list",
    });
    expect(msgs[1]).toMatchObject({
      jsonrpc: "2.0",
      id: 2,
      method: "sandbox/stop",
      params: { name: "test" },
    });
  });

  it("sends a notification without id", () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.transport.notify("log", { message: "hello" });

    const msgs = mock.getOutputMessages();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({
      jsonrpc: "2.0",
      method: "log",
      params: { message: "hello" },
    });
    expect(msgs[0]).not.toHaveProperty("id");
  });

  it("resolves a pending request when response arrives", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    const promise = mock.transport.request("sandbox/list");

    mock.sendToPlugin({
      jsonrpc: "2.0",
      id: 1,
      result: [{ name: "test-sb", status: "running" }],
    });

    await new Promise((r) => setTimeout(r, 20));
    const result = await promise;
    expect(result).toEqual([{ name: "test-sb", status: "running" }]);
  });

  it("rejects a pending request on error response", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    let caughtError: Error | undefined;
    const promise = mock.transport
      .request("sandbox/stop", { name: "missing" })
      .catch((err: Error) => {
        caughtError = err;
      });

    mock.sendToPlugin({
      jsonrpc: "2.0",
      id: 1,
      error: { code: -32002, message: "Sandbox not found" },
    });

    await new Promise((r) => setTimeout(r, 20));
    await promise;

    expect(caughtError).toBeInstanceOf(Error);
    expect(caughtError!.message).toContain("Sandbox not found");
  });

  it("dispatches incoming notifications to handlers", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    const handler = vi.fn();
    mock.transport.onNotification("initialize", handler);

    mock.sendToPlugin({
      jsonrpc: "2.0",
      method: "initialize",
      params: { pluginId: "test" },
    });

    await new Promise((r) => setTimeout(r, 20));
    expect(handler).toHaveBeenCalledWith({ pluginId: "test" });
  });

  it("handles incoming requests and responds", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.transport.onRequest("ping", async () => "pong");

    mock.sendToPlugin({
      jsonrpc: "2.0",
      id: 99,
      method: "ping",
      params: {},
    });

    await new Promise((r) => setTimeout(r, 20));

    const msgs = mock.getOutputMessages();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({
      jsonrpc: "2.0",
      id: 99,
      result: "pong",
    });
  });

  it("responds with error for unknown request methods", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.sendToPlugin({
      jsonrpc: "2.0",
      id: 42,
      method: "unknown/method",
      params: {},
    });

    await new Promise((r) => setTimeout(r, 20));

    const msgs = mock.getOutputMessages();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({
      jsonrpc: "2.0",
      id: 42,
      error: { code: -32601 },
    });
  });

  it("responds with error when request handler throws", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.transport.onRequest("fail", async () => {
      throw new Error("handler crashed");
    });

    mock.sendToPlugin({
      jsonrpc: "2.0",
      id: 7,
      method: "fail",
      params: {},
    });

    await new Promise((r) => setTimeout(r, 20));

    const msgs = mock.getOutputMessages();
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({
      jsonrpc: "2.0",
      id: 7,
      error: { code: -32603, message: "handler crashed" },
    });
  });

  it("ignores unregistered notifications", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.sendToPlugin({
      jsonrpc: "2.0",
      method: "event/unknown",
      params: {},
    });

    await new Promise((r) => setTimeout(r, 20));
  });

  it("ignores responses with unknown ids", async () => {
    const mock = createMockTransport();
    cleanup = mock.cleanup;

    mock.sendToPlugin({
      jsonrpc: "2.0",
      id: 999,
      result: "stale",
    });

    await new Promise((r) => setTimeout(r, 20));
  });
});
