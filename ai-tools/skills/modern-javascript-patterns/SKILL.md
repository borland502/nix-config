---
name: modern-javascript-patterns
description: Master ES6+ features including async/await, destructuring, spread operators, arrow functions, promises, modules, iterators, generators, and functional programming patterns for writing clean, efficient JavaScript code. Use when refactoring legacy code, implementing modern patterns, or optimizing JavaScript applications. For TypeScript type system design, see typescript-advanced-types.
origin: wshobson/agents
---

# Modern JavaScript Patterns

## When to Use

- Refactoring legacy JavaScript to modern syntax
- Migrating from callbacks to Promises/async-await
- Implementing functional programming patterns
- Writing maintainable, performant code

## ES6+ Core Features

### Arrow Functions and Lexical `this`

```javascript
const add = (a, b) => a + b;
const createUser = (name, age) => ({ name, age }); // Wrap object in ()

class Counter {
  increment = () => { this.count++; }; // Arrow preserves 'this' in callbacks
}
```

### Destructuring

```javascript
const { name, address: { city }, id, ...rest } = user; // nested + rest
const [first, , third, ...tail] = numbers;             // skip + rest
const { age = 25 } = user;                             // default value
function greet({ name, age = 18 }) { ... }             // param destructuring
```

### Spread and Rest

```javascript
const combined = [...arr1, ...arr2];
const merged = { ...defaults, ...overrides };    // later key wins
const [head, ...tail] = items;
function sum(...numbers) { return numbers.reduce((t, n) => t + n, 0); }
```

### Optional Chaining and Nullish Coalescing

```javascript
const city = user?.address?.city;     // safe deep access
const result = obj.method?.();        // safe method call
const value = null ?? "default";      // only null/undefined triggers default (0/"" preserved)
a ??= "default";   // assign if null/undefined
obj.count ||= 1;   // assign if falsy
```

### Template Literals

```javascript
const greeting = `Hello, ${name}!`;
const html = `<div>${title}</div>`;
const total = `Total: $${(price * 1.2).toFixed(2)}`;
```

## Asynchronous Patterns

### async/await (preferred)

```javascript
async function getUserData(id) {
  try {
    const user = await fetchUser(id);
    const posts = await fetchUserPosts(user.id);
    return { user, posts };
  } catch (error) {
    throw error;
  }
}

// Sequential vs parallel
const user1 = await fetchUser(1); // waits for each
const [u1, u2] = await Promise.all([fetchUser(1), fetchUser(2)]); // parallel
```

### Promise Combinators

```javascript
Promise.all(promises)          // fail-fast: one rejection fails all
Promise.allSettled(promises)   // all complete; check result.status
Promise.race(promises)         // first to settle (resolve or reject)
Promise.any(promises)          // first to resolve; fails if all reject
```

### Retry with Backoff

```javascript
async function fetchWithRetry(url, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      return await fetch(url);
    } catch (err) {
      if (i === retries - 1) throw err;
      await new Promise(r => setTimeout(r, 1000 * (i + 1)));
    }
  }
}
```

### Timeout Wrapper

```javascript
async function withTimeout(promise, ms) {
  const timeout = new Promise((_, reject) =>
    setTimeout(() => reject(new Error("Timeout")), ms)
  );
  return Promise.race([promise, timeout]);
}
```

## Functional Programming Patterns

```javascript
// Composition utilities
const pipe = (...fns) => x => fns.reduce((v, f) => f(v), x);
const compose = (...fns) => x => fns.reduceRight((v, f) => f(v), x);

// Memoization
const memoize = fn => {
  const cache = new Map();
  return (...args) => {
    const key = JSON.stringify(args);
    return cache.has(key) ? cache.get(key) : cache.set(key, fn(...args)).get(key);
  };
};

// Immutable array/object ops
const newArr = [...arr, newItem];
const newObj = { ...obj, key: newValue };
const deep = structuredClone(obj);
```

## Modern Class Features

```javascript
class User {
  #password;                          // private field
  static count = 0;                   // static field
  constructor(name) { this.name = name; User.count++; }
  get displayName() { return this.name.toUpperCase(); }
  #validate() { ... }                 // private method
}
```

## Modules (ES6)

```javascript
export const PI = 3.14;
export function add(a, b) { return a + b; }
export default class App { ... }

import App, { PI, add } from "./math.js";
const { add } = await import("./math.js"); // dynamic import (code splitting)
```

## Generators

```javascript
function* range(start, end) {
  for (let i = start; i <= end; i++) yield i;
}

async function* paginate(url) {
  let page = 1;
  while (true) {
    const data = await fetch(`${url}?page=${page++}`).then(r => r.json());
    if (!data.length) break;
    yield data;
  }
}

for await (const page of paginate("/api/items")) { process(page); }
```

## Best Practices

- Use `const` by default; `let` only when reassignment is needed; avoid `var`
- Prefer `async/await` over `.then()` chains
- Use optional chaining (`?.`) to prevent "Cannot read property of undefined"
- Prefer `??` over `||` for defaults when `0`, `""`, or `false` are valid values
- Avoid mutating data — use spread/array methods for immutable updates
- Write pure functions — same inputs always produce the same output
- Use `structuredClone` for true deep copies
