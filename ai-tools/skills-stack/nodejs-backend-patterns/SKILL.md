---
name: nodejs-backend-patterns
description: Build production-ready Node.js backend services with Express/Fastify, implementing middleware patterns, error handling, authentication, database integration, and API design best practices. Use when creating Node.js servers, REST APIs, GraphQL backends, or microservices architectures.
origin: wshobson/agents
---

# Node.js Backend Patterns

## When to Use

- Building REST APIs or GraphQL servers
- Creating microservices with Node.js
- Implementing authentication and authorization (JWT, OIDC)
- Setting up middleware, error handling, rate limiting
- Integrating SQL/NoSQL databases with connection pooling

## Framework Setup

### Express

```typescript
import express from "express";
import helmet from "helmet";
import cors from "cors";
import compression from "compression";

const app = express();
app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(",") }));
app.use(compression());
app.use(express.json({ limit: "10mb" }));
```

### Fastify (higher throughput, built-in schema validation)

```typescript
import Fastify from "fastify";
const fastify = Fastify({ logger: true });
await fastify.register(import("@fastify/helmet"));
await fastify.register(import("@fastify/cors"), { origin: true });

fastify.post<{ Body: { name: string }; Reply: { id: string } }>(
  "/users",
  { schema: { body: { type: "object", required: ["name"], properties: { name: { type: "string" } } } } },
  async (req) => ({ id: "123", name: req.body.name })
);
```

## Layered Architecture

```
src/
├── controllers/    # HTTP request/response only — delegate to service
├── services/       # Business logic — no HTTP knowledge
├── repositories/   # Data access — no business logic
├── middleware/     # Auth, validation, rate limiting, logging
├── routes/         # Route definitions
└── types/          # Shared TypeScript types
```

### Custom Error Classes

```typescript
export class AppError extends Error {
  constructor(public message: string, public statusCode = 500, public isOperational = true) {
    super(message);
    Object.setPrototypeOf(this, AppError.prototype);
  }
}
export class NotFoundError   extends AppError { constructor(msg = "Not found") { super(msg, 404); } }
export class ValidationError extends AppError { constructor(msg: string, public errors?: any[]) { super(msg, 400); } }
export class UnauthorizedError extends AppError { constructor(msg = "Unauthorized") { super(msg, 401); } }
```

### Global Error Handler

```typescript
export const errorHandler = (err: Error, req: Request, res: Response, next: NextFunction) => {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({ status: "error", message: err.message });
  }
  logger.error({ error: err.message, stack: err.stack, url: req.url });
  res.status(500).json({ status: "error", message: process.env.NODE_ENV === "production" ? "Internal server error" : err.message });
};

export const asyncHandler = (fn: (req: Request, res: Response, next: NextFunction) => Promise<any>) =>
  (req: Request, res: Response, next: NextFunction) => Promise.resolve(fn(req, res, next)).catch(next);
```

## Middleware Patterns

### JWT Authentication

```typescript
export const authenticate = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const token = req.headers.authorization?.replace("Bearer ", "");
    if (!token) throw new UnauthorizedError("No token provided");
    req.user = jwt.verify(token, process.env.JWT_SECRET!) as JWTPayload;
    next();
  } catch { next(new UnauthorizedError("Invalid token")); }
};
```

### Zod Validation Middleware

```typescript
export const validate = (schema: AnyZodObject) =>
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await schema.parseAsync({ body: req.body, query: req.query, params: req.params });
      next();
    } catch (err) {
      if (err instanceof ZodError) next(new ValidationError("Validation failed", err.errors));
      else next(err);
    }
  };
```

### Rate Limiting (Redis-backed)

```typescript
export const apiLimiter = rateLimit({
  store: new RedisStore({ client: redis, prefix: "rl:" }),
  windowMs: 15 * 60 * 1000, // 15 min
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
});
```

## Database Patterns

### PostgreSQL with Connection Pool

```typescript
import { Pool } from "pg";
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20, idleTimeoutMillis: 30_000, connectionTimeoutMillis: 2_000,
});
```

### Transactions

```typescript
const client = await pool.connect();
try {
  await client.query("BEGIN");
  await client.query("INSERT INTO ...", [...]);
  await client.query("UPDATE ...", [...]);
  await client.query("COMMIT");
} catch (err) {
  await client.query("ROLLBACK");
  throw err;
} finally {
  client.release();
}
```

## Authentication

JWT access tokens (15m) + refresh tokens (7d stored in httpOnly cookies). Hash passwords with bcrypt (rounds ≥ 10). Never return passwords in responses.

## Best Practices

1. Always use TypeScript with `strict: true`
2. Use Zod or Joi for input validation at route boundaries
3. Never hardcode secrets — use environment variables
4. Use structured logging (Pino) with log levels
5. Add rate limiting to all public endpoints; stricter limits on auth routes
6. Use connection pooling for every database
7. Implement health check endpoints (`/health`) for monitoring
8. Handle graceful shutdown: `process.on("SIGTERM")` → drain connections
9. Use HTTPS in production; set appropriate CORS origin lists (not `*`)
10. Write integration tests against a real database, not mocks
