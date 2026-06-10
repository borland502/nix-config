---
name: javascript-testing-patterns
description: Implement comprehensive testing strategies using Jest, Vitest, and Testing Library for unit tests, integration tests, and end-to-end testing with mocking, fixtures, and test-driven development. Use when writing JavaScript/TypeScript tests, setting up test infrastructure, or implementing TDD/BDD workflows.
origin: wshobson/agents
---

# JavaScript Testing Patterns

Comprehensive guide for implementing robust testing strategies in JavaScript/TypeScript applications using modern testing frameworks and best practices.

## When to Use

- Setting up test infrastructure for new projects
- Writing unit tests for functions and classes
- Creating integration tests for APIs and services
- Mocking external dependencies and APIs
- Testing React or other frontend components
- Implementing TDD

## Testing Frameworks

### Jest

```typescript
// jest.config.ts
import type { Config } from "jest";
const config: Config = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.ts", "**/?(*.)+(spec|test).ts"],
  collectCoverageFrom: ["src/**/*.ts", "!src/**/*.d.ts"],
  coverageThreshold: { global: { branches: 80, functions: 80, lines: 80, statements: 80 } },
  setupFilesAfterEnv: ["<rootDir>/src/test/setup.ts"],
};
export default config;
```

### Vitest (preferred for Vite projects)

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      exclude: ["**/*.d.ts", "**/*.config.ts", "**/dist/**"],
    },
    setupFiles: ["./src/test/setup.ts"],
  },
});
```

## Unit Testing Patterns

### Pure Functions

```typescript
import { describe, it, expect } from "vitest";
import { add, divide } from "./calculator";

describe("Calculator", () => {
  it("adds two numbers", () => expect(add(2, 3)).toBe(5));
  it("throws on division by zero", () => expect(() => divide(10, 0)).toThrow("Division by zero"));
});
```

### Classes

```typescript
describe("UserService", () => {
  let service: UserService;
  beforeEach(() => { service = new UserService(); });

  it("creates a user", () => {
    const user = { id: "1", name: "John", email: "john@example.com" };
    expect(service.create(user)).toEqual(user);
  });

  it("throws if user already exists", () => {
    const user = { id: "1", name: "John", email: "john@example.com" };
    service.create(user);
    expect(() => service.create(user)).toThrow("User already exists");
  });
});
```

### Async Functions

```typescript
// Mock fetch globally
global.fetch = vi.fn();

describe("ApiService", () => {
  beforeEach(() => vi.clearAllMocks());

  it("fetches user successfully", async () => {
    const mockUser = { id: "1", name: "John" };
    (fetch as any).mockResolvedValueOnce({ ok: true, json: async () => mockUser });
    expect(await service.fetchUser("1")).toEqual(mockUser);
  });

  it("throws when not found", async () => {
    (fetch as any).mockResolvedValueOnce({ ok: false });
    await expect(service.fetchUser("999")).rejects.toThrow("User not found");
  });
});
```

## Mocking Patterns

### Module Mocking

```typescript
vi.mock("nodemailer", () => ({
  default: {
    createTransport: vi.fn(() => ({
      sendMail: vi.fn().mockResolvedValue({ messageId: "123" }),
    })),
  },
}));
```

### Dependency Injection (preferred for testability)

```typescript
// Interface-based DI makes mocking trivial
mockRepository = { findById: vi.fn(), create: vi.fn() };
service = new UserService(mockRepository);

vi.mocked(mockRepository.findById).mockResolvedValue(mockUser);
```

### Spies

```typescript
const loggerSpy = vi.spyOn(logger, "info");
afterEach(() => loggerSpy.mockRestore());
expect(loggerSpy).toHaveBeenCalledWith("Processing order 123");
```

## Integration Testing

Use `supertest` for HTTP endpoints and a real test database. Truncate tables in `beforeEach`, tear down in `afterAll`. Never mock the database in integration tests.

## Frontend Testing with Testing Library

Prefer semantic queries (`getByRole`, `getByPlaceholderText`) over `data-testid`. Use `renderHook` + `act` for hooks.

## Test Fixtures

```typescript
import { faker } from "@faker-js/faker";
export function createUserFixture(overrides?: Partial<User>): User {
  return {
    id: faker.string.uuid(),
    name: faker.person.fullName(),
    email: faker.internet.email(),
    createdAt: faker.date.past(),
    ...overrides,
  };
}
```

## Best Practices

1. Follow **AAA** — Arrange, Act, Assert
2. One logical assertion per test
3. Test behavior, not implementation details
4. Mock external I/O; use real code for pure logic
5. Use `beforeEach` for isolated setup; `afterEach` for cleanup
6. Test edge cases and error paths, not just happy paths
7. Use `data-testid` sparingly — prefer semantic queries
8. Aim for 80%+ meaningful coverage (not just line coverage)
