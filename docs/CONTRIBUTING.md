# Contributing

Contributions are welcome. This guide will help you get started.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/homebrew-uttr.git
   cd homebrew-uttr
   ```
3. **Set up the development environment** — See [Development Guide](development.md)

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### 2. Make Your Changes

- Keep changes focused and atomic
- Follow the code style guidelines below
- Update documentation if needed

### 3. Test Your Changes

- Build and run in Xcode
- Test the affected functionality manually
- Verify transcription still works end-to-end

### 4. Commit Your Changes

```bash
# Good
git commit -m "Add language detection hint to FluidAudioProvider"
git commit -m "Fix hotkey not registering on app restart"

# Bad
git commit -m "Fixed stuff"
```

### 5. Push and Create a Pull Request

```bash
git push origin feature/your-feature-name
```

Open a Pull Request with a clear description of what changed and why, and steps to test.

## Code Style

- **One file per component** — each Swift file has a single responsibility
- **Use Logger** — all logging through the `Logger` class, not `print()`
- **Prefer async/await** — for asynchronous operations
- **Follow existing patterns** — look at similar code in the codebase

## Architecture Guidelines

uttr is a single-tier Swift app. All transcription runs in-process via FluidAudio on the Neural Engine. There is no server tier, no Python, and no network communication after the initial model download.

See [Architecture](architecture.md) for the full component map.

## What to Contribute

Good starting points: bug fixes, documentation improvements, performance optimizations. For new features, open an issue to discuss first.

## Questions?

Open an issue for bugs or feature requests, or start a discussion for questions.
