# Calcusome

## After every push

After every `git push`, build the latest version and replace the app in `/Applications`.
Run these from the repository root:

```bash
cd apple/App && xcodegen
```

```bash
xcodebuild -scheme Calcusome -configuration Release -destination 'platform=macOS' -derivedDataPath DerivedData build
```

```bash
osascript -e 'quit app "Calcusome"'; rm -rf /Applications/Calcusome.app && cp -R DerivedData/Build/Products/Release/Calcusome.app /Applications/ && open /Applications/Calcusome.app
```

- Run the second and third commands from `apple/App`.
- Remove the old app before the copy. `cp -R` into an existing `.app` merges the bundles and can leave stale files.
- If the build fails, do not touch `/Applications/Calcusome.app`. Report the error.
