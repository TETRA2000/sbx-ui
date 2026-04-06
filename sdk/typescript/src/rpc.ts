import { createInterface } from "readline";

// JSON-RPC 2.0 types
export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: unknown;
  error?: JsonRpcError;
}

export interface JsonRpcNotification {
  jsonrpc: "2.0";
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

type JsonRpcMessage = JsonRpcRequest | JsonRpcResponse | JsonRpcNotification;

type RequestHandler = (
  params: Record<string, unknown>
) => Promise<unknown> | unknown;
type NotificationHandler = (params: Record<string, unknown>) => void;

/**
 * JSON-RPC 2.0 transport over stdin/stdout.
 */
export class RpcTransport {
  private nextId = 1;
  private pendingRequests = new Map<
    string | number,
    {
      resolve: (value: unknown) => void;
      reject: (error: Error) => void;
    }
  >();
  private requestHandlers = new Map<string, RequestHandler>();
  private notificationHandlers = new Map<string, NotificationHandler>();

  constructor() {
    const rl = createInterface({ input: process.stdin });
    rl.on("line", (line: string) => {
      if (!line.trim()) return;
      try {
        const message: JsonRpcMessage = JSON.parse(line);
        this.handleMessage(message);
      } catch {
        process.stderr.write(`Failed to parse JSON-RPC message: ${line}\n`);
      }
    });
    rl.on("close", () => process.exit(0));
  }

  /** Register a handler for incoming requests from the host. */
  onRequest(method: string, handler: RequestHandler): void {
    this.requestHandlers.set(method, handler);
  }

  /** Register a handler for incoming notifications from the host. */
  onNotification(method: string, handler: NotificationHandler): void {
    this.notificationHandlers.set(method, handler);
  }

  /** Send a request to the host and wait for a response. */
  async request(
    method: string,
    params?: Record<string, unknown>
  ): Promise<unknown> {
    const id = this.nextId++;
    const message: JsonRpcRequest = { jsonrpc: "2.0", id, method, params };
    this.send(message);

    return new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { resolve, reject });
    });
  }

  /** Send a notification to the host (no response expected). */
  notify(method: string, params?: Record<string, unknown>): void {
    const message: JsonRpcNotification = { jsonrpc: "2.0", method, params };
    this.send(message);
  }

  private send(message: JsonRpcMessage): void {
    process.stdout.write(JSON.stringify(message) + "\n");
  }

  private handleMessage(message: JsonRpcMessage): void {
    if ("id" in message && "result" in message) {
      // Response
      this.handleResponse(message as JsonRpcResponse);
    } else if ("id" in message && "method" in message) {
      // Request
      this.handleRequest(message as JsonRpcRequest);
    } else if ("method" in message) {
      // Notification
      this.handleNotification(message as JsonRpcNotification);
    }
  }

  private handleResponse(response: JsonRpcResponse): void {
    const pending = this.pendingRequests.get(response.id!);
    if (!pending) return;
    this.pendingRequests.delete(response.id!);

    if (response.error) {
      pending.reject(
        new Error(`${response.error.message} (code: ${response.error.code})`)
      );
    } else {
      pending.resolve(response.result);
    }
  }

  private async handleRequest(request: JsonRpcRequest): Promise<void> {
    const handler = this.requestHandlers.get(request.method);
    if (!handler) {
      this.send({
        jsonrpc: "2.0",
        id: request.id,
        error: { code: -32601, message: `Method not found: ${request.method}` },
      } as JsonRpcResponse);
      return;
    }

    try {
      const result = await handler(request.params ?? {});
      this.send({
        jsonrpc: "2.0",
        id: request.id,
        result,
      } as JsonRpcResponse);
    } catch (err) {
      this.send({
        jsonrpc: "2.0",
        id: request.id,
        error: {
          code: -32603,
          message: err instanceof Error ? err.message : String(err),
        },
      } as JsonRpcResponse);
    }
  }

  private handleNotification(notification: JsonRpcNotification): void {
    const handler = this.notificationHandlers.get(notification.method);
    if (handler) {
      handler(notification.params ?? {});
    }
  }
}
