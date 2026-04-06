import { RpcTransport } from "./rpc.js";
import type {
  Sandbox,
  PortMapping,
  PolicyRule,
  EnvVar,
  ExecResult,
  FileReadResult,
} from "./types.js";

export type {
  Sandbox,
  PortMapping,
  PolicyRule,
  EnvVar,
  ExecResult,
  FileReadResult,
};

type EventHandler = (params: Record<string, unknown>) => void | Promise<void>;

/**
 * sbx-ui Plugin SDK for TypeScript/Node.js.
 *
 * @example
 * ```ts
 * import { SbxPlugin } from '@sbx-ui/plugin-sdk';
 *
 * const plugin = new SbxPlugin();
 *
 * plugin.on('initialize', async () => {
 *   const sandboxes = await plugin.sandbox.list();
 *   await plugin.ui.log(`Found ${sandboxes.length} sandboxes`);
 * });
 *
 * plugin.on('event/onSandboxCreated', async (params) => {
 *   await plugin.ui.notify('New sandbox', `Created: ${params.name}`);
 * });
 *
 * plugin.start();
 * ```
 */
export class SbxPlugin {
  private rpc: RpcTransport;
  private handlers = new Map<string, EventHandler>();

  /** Sandbox operations. */
  readonly sandbox: SandboxApi;
  /** Port management. */
  readonly ports: PortsApi;
  /** Environment variable management. */
  readonly envVars: EnvVarsApi;
  /** Network policy management. */
  readonly policy: PolicyApi;
  /** File I/O on the host. */
  readonly file: FileApi;
  /** UI notifications and logging. */
  readonly ui: UiApi;

  constructor() {
    this.rpc = new RpcTransport();
    this.sandbox = new SandboxApi(this.rpc);
    this.ports = new PortsApi(this.rpc);
    this.envVars = new EnvVarsApi(this.rpc);
    this.policy = new PolicyApi(this.rpc);
    this.file = new FileApi(this.rpc);
    this.ui = new UiApi(this.rpc);
  }

  /** Register a handler for host notifications (initialize, shutdown, event/*). */
  on(event: string, handler: EventHandler): void {
    this.handlers.set(event, handler);
  }

  /** Start the plugin — begins listening for messages from the host. */
  start(): void {
    // Wire up notification handlers
    for (const [event, handler] of this.handlers) {
      this.rpc.onNotification(event, (params) => {
        Promise.resolve(handler(params)).catch((err) => {
          process.stderr.write(`Handler error for ${event}: ${err}\n`);
        });
      });
    }
  }
}

class SandboxApi {
  constructor(private rpc: RpcTransport) {}

  async list(): Promise<Sandbox[]> {
    return (await this.rpc.request("sandbox/list")) as Sandbox[];
  }

  async exec(
    name: string,
    command: string,
    args: string[] = []
  ): Promise<ExecResult> {
    return (await this.rpc.request("sandbox/exec", {
      name,
      command,
      args,
    })) as ExecResult;
  }

  async stop(name: string): Promise<void> {
    await this.rpc.request("sandbox/stop", { name });
  }

  async run(
    agent: string,
    workspace: string,
    name?: string
  ): Promise<Sandbox> {
    return (await this.rpc.request("sandbox/run", {
      agent,
      workspace,
      name,
    })) as Sandbox;
  }
}

class PortsApi {
  constructor(private rpc: RpcTransport) {}

  async list(name: string): Promise<PortMapping[]> {
    return (await this.rpc.request("sandbox/ports/list", {
      name,
    })) as PortMapping[];
  }

  async publish(
    name: string,
    hostPort: number,
    sbxPort: number
  ): Promise<PortMapping> {
    return (await this.rpc.request("sandbox/ports/publish", {
      name,
      hostPort,
      sbxPort,
    })) as PortMapping;
  }

  async unpublish(
    name: string,
    hostPort: number,
    sbxPort: number
  ): Promise<void> {
    await this.rpc.request("sandbox/ports/unpublish", {
      name,
      hostPort,
      sbxPort,
    });
  }
}

class EnvVarsApi {
  constructor(private rpc: RpcTransport) {}

  async list(name: string): Promise<EnvVar[]> {
    return (await this.rpc.request("sandbox/envVars/list", {
      name,
    })) as EnvVar[];
  }

  async set(name: string, key: string, value: string): Promise<void> {
    await this.rpc.request("sandbox/envVars/set", { name, key, value });
  }
}

class PolicyApi {
  constructor(private rpc: RpcTransport) {}

  async list(): Promise<PolicyRule[]> {
    return (await this.rpc.request("policy/list")) as PolicyRule[];
  }

  async allow(resources: string): Promise<PolicyRule> {
    return (await this.rpc.request("policy/allow", {
      resources,
    })) as PolicyRule;
  }

  async deny(resources: string): Promise<PolicyRule> {
    return (await this.rpc.request("policy/deny", { resources })) as PolicyRule;
  }

  async remove(resource: string): Promise<void> {
    await this.rpc.request("policy/remove", { resource });
  }
}

class FileApi {
  constructor(private rpc: RpcTransport) {}

  async read(path: string): Promise<FileReadResult> {
    return (await this.rpc.request("file/read", { path })) as FileReadResult;
  }

  async write(path: string, content: string): Promise<void> {
    await this.rpc.request("file/write", { path, content });
  }
}

class UiApi {
  constructor(private rpc: RpcTransport) {}

  async notify(
    title: string,
    message: string,
    level: string = "info"
  ): Promise<void> {
    await this.rpc.request("ui/notify", { title, message, level });
  }

  async log(message: string, level: string = "info"): Promise<void> {
    await this.rpc.request("ui/log", { message, level });
  }
}
