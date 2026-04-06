import { SbxPlugin } from "@sbx-ui/plugin-sdk";

const plugin = new SbxPlugin();

plugin.on("initialize", async () => {
  const sandboxes = await plugin.sandbox.list();
  await plugin.ui.log(
    `Hello from plugin! Found ${sandboxes.length} sandbox(es).`
  );

  for (const sandbox of sandboxes) {
    await plugin.ui.log(
      `  - ${sandbox.name} [${sandbox.status}] workspace: ${sandbox.workspace}`
    );
  }
});

plugin.on("event/onSandboxCreated", async (params) => {
  await plugin.ui.notify(
    "Sandbox Created",
    `New sandbox: ${params.name as string}`
  );
});

plugin.start();
