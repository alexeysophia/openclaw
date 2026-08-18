// Covers model-catalog failure and recovery on the new-session page.
import { expect, it } from "vitest";
import {
  createNewSessionPageE2eSuite,
  installMockGateway,
} from "./new-session-page.test-support.ts";

const suite = createNewSessionPageE2eSuite();

suite.define(() => {
  it("loads the model catalog when chat metadata is unavailable", async () => {
    const context = await suite.browser.newContext({
      locale: "en-US",
      serviceWorkers: "block",
      viewport: { height: 900, width: 1280 },
    });
    const page = await context.newPage();
    const models = [
      {
        available: true,
        id: "gpt-5.6-luna",
        name: "GPT-5.6 Luna",
        provider: "openai",
      },
      {
        available: true,
        id: "gpt-5.6-sol",
        name: "GPT-5.6 Sol",
        provider: "openai",
      },
      {
        available: true,
        id: "gpt-5.6-terra",
        name: "GPT-5.6 Terra",
        provider: "openai",
      },
    ];
    const gateway = await installMockGateway(page, {
      agentModel: "openai/gpt-5.6-luna",
      methodResponses: {
        "chat.metadata": {
          __mockError: {
            code: "UNAVAILABLE",
            message: 'prepared chat metadata owner is unavailable for agent "main"',
          },
        },
      },
      models,
    });

    try {
      await page.goto(`${suite.server.baseUrl}new`);
      const modelRequest = await gateway.waitForRequest("models.list");
      expect(modelRequest.params).toEqual({
        agentId: "main",
        preparedOnly: true,
        view: "configured",
      });

      const modelSelect = page.locator('[data-chat-model-select="true"]');
      await modelSelect.click();
      await expect.poll(() => page.locator("[data-chat-model-option]").count()).toBe(3);
      expect(await page.locator('[data-chat-model-catalog-state="error"]').count()).toBe(0);
      expect(await gateway.getRequests("chat.metadata")).toHaveLength(0);
    } finally {
      await context.close();
    }
  });

  it("restores the model picker after startup-sidecars catalog becomes available", async () => {
    const context = await suite.browser.newContext({
      locale: "en-US",
      serviceWorkers: "block",
      viewport: { height: 900, width: 1280 },
    });
    const page = await context.newPage();
    const recoveredModel = {
      available: true,
      id: "gpt-5.6-luna",
      name: "Recovered GPT-5.6 Luna",
      provider: "openai",
      reasoning: true,
    };
    const gateway = await installMockGateway(page, {
      methodResponses: {
        "models.list": {
          sequence: [
            {
              __mockError: {
                code: "UNAVAILABLE",
                details: { reason: "startup-sidecars" },
                message: "gateway startup sidecars are still initializing",
                retryable: true,
                retryAfterMs: 100,
              },
            },
            { commands: [], models: [recoveredModel] },
          ],
        },
      },
    });

    try {
      await page.goto(`${suite.server.baseUrl}new`);
      await expect.poll(async () => (await gateway.getRequests("models.list")).length).toBe(2);

      const modelSelect = page.locator(
        '.new-session-page__composer [data-chat-model-select="true"]',
      );
      await modelSelect.click();
      await expect
        .poll(() => page.locator('[data-chat-model-option="openai/gpt-5.6-luna"]').textContent())
        .toContain(recoveredModel.name);

      expect(await gateway.getRequests("models.list")).toEqual([
        expect.objectContaining({
          params: { agentId: "main", preparedOnly: true, view: "configured" },
        }),
        expect.objectContaining({
          params: { agentId: "main", preparedOnly: true, view: "configured" },
        }),
      ]);
    } finally {
      await context.close();
    }
  });
});
