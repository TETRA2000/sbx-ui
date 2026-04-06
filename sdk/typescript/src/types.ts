/** A Docker Sandbox instance. */
export interface Sandbox {
  name: string;
  agent: string;
  status: "running" | "stopped" | "creating" | "removing";
  workspace: string;
  ports: PortMapping[];
}

/** A port mapping between host and sandbox. */
export interface PortMapping {
  hostPort: number;
  sandboxPort: number;
  protocolType: string;
}

/** A network policy rule. */
export interface PolicyRule {
  id: string;
  type: string;
  decision: "allow" | "deny";
  resources: string;
}

/** An environment variable. */
export interface EnvVar {
  key: string;
  value: string;
}

/** Result of executing a command in a sandbox. */
export interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

/** File read result. */
export interface FileReadResult {
  path: string;
  content: string;
}
