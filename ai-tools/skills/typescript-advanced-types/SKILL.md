---
name: typescript-advanced-types
description: Master TypeScript's advanced type system including generics, conditional types, mapped types, template literals, and utility types for building type-safe applications. Use when implementing complex type logic, creating reusable type utilities, or ensuring compile-time type safety in TypeScript projects. For async/await and Promise patterns, see modern-javascript-patterns.
origin: wshobson/agents
---

# TypeScript Advanced Types

## When to Use

- Building type-safe libraries or frameworks
- Creating reusable generic components
- Implementing complex type inference logic
- Designing type-safe API clients or state machines
- Migrating JavaScript codebases to TypeScript

## Generics

```typescript
function identity<T>(value: T): T { return value; }

// Constraints
function logLength<T extends { length: number }>(item: T): T {
  console.log(item.length);
  return item;
}

// Multiple type parameters
function merge<T, U>(obj1: T, obj2: U): T & U { return { ...obj1, ...obj2 }; }
```

## Conditional Types

```typescript
type IsString<T> = T extends string ? true : false;

// infer — extract inner types
type ReturnType<T> = T extends (...args: any[]) => infer R ? R : never;
type ElementType<T> = T extends (infer U)[] ? U : never;
type PromiseType<T> = T extends Promise<infer U> ? U : never;

// Distributive
type ToArray<T> = T extends any ? T[] : never;
type StrOrNumArr = ToArray<string | number>; // string[] | number[]
```

## Mapped Types

```typescript
// Modify modifiers
type Readonly<T> = { readonly [P in keyof T]: T[P] };
type Partial<T>  = { [P in keyof T]?: T[P] };
type Required<T> = { [P in keyof T]-?: T[P] };  // remove optional

// Key remapping
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K]
};

// Filtering properties by type
type PickByType<T, U> = {
  [K in keyof T as T[K] extends U ? K : never]: T[K]
};
```

## Template Literal Types

```typescript
type EventName = "click" | "focus" | "blur";
type EventHandler = `on${Capitalize<EventName>}`;  // "onClick" | "onFocus" | "onBlur"

// String manipulation
type Upper = Uppercase<"hello">;     // "HELLO"
type Lower = Lowercase<"HELLO">;     // "hello"
type Cap   = Capitalize<"john">;     // "John"
```

## Utility Types (Built-In)

```typescript
type A = Partial<User>               // all optional
type B = Required<Partial<User>>     // all required
type C = Readonly<User>              // all readonly
type D = Pick<User, "name" | "email">
type E = Omit<User, "password">
type F = Exclude<"a"|"b"|"c", "a">  // "b" | "c"
type G = Extract<"a"|"b"|"c", "a"|"b"> // "a" | "b"
type H = NonNullable<string|null|undefined> // string
type I = Record<"home"|"about", { title: string }>
```

## Custom Utility Types

```typescript
// Deep Readonly
type DeepReadonly<T> = {
  readonly [P in keyof T]: T[P] extends object
    ? T[P] extends Function ? T[P] : DeepReadonly<T[P]>
    : T[P];
};

// Deep Partial
type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends object
    ? T[P] extends Array<infer U> ? Array<DeepPartial<U>> : DeepPartial<T[P]>
    : T[P];
};
```

## Discriminated Unions

```typescript
type AsyncState<T> =
  | { status: "loading" }
  | { status: "success"; data: T }
  | { status: "error"; error: string };

function handle<T>(state: AsyncState<T>) {
  switch (state.status) {
    case "success": console.log(state.data); break;  // narrowed to data
    case "error":   console.log(state.error); break; // narrowed to error
  }
}
```

## Type Guards

```typescript
function isString(value: unknown): value is string { return typeof value === "string"; }

function isArrayOf<T>(value: unknown, guard: (item: unknown) => item is T): value is T[] {
  return Array.isArray(value) && value.every(guard);
}

// Assertion function
function assertIsString(value: unknown): asserts value is string {
  if (typeof value !== "string") throw new Error("Not a string");
}
```

## Type-Safe Patterns

```typescript
// Event emitter with type-safe events
type EventMap = { "user:created": { id: string }; "user:deleted": { id: string } };
class TypedEmitter<T extends Record<string, any>> {
  on<K extends keyof T>(event: K, cb: (data: T[K]) => void): void { ... }
  emit<K extends keyof T>(event: K, data: T[K]): void { ... }
}

// Type testing
type AssertEqual<T, U> = [T] extends [U] ? [U] extends [T] ? true : false : false;
```

## Best Practices

- Use `unknown` instead of `any` at system boundaries — it forces type checking
- Prefer `interface` for object shapes (better error messages); `type` for unions and aliases
- Let TypeScript infer when the type is obvious — explicit annotations are for non-obvious cases
- Use `strict: true` in `tsconfig.json`; enable all strict flags
- Use discriminated unions rather than optional properties for mutually exclusive states
- Use `readonly` to prevent accidental mutation
- Write type tests (`AssertEqual`) for complex utility types to catch regressions
