# App icon artwork

The icon uses the green emblem from the [user-provided clinic logo](https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQ0e_5ksykd5I2mfkQNJVh4VAT2wekWE8Rv8kKDIHB_MR0EE3NplweXsb5b&s=10).
The supplied image is retained unchanged as `logo-reference.png`. The wordmark is
omitted so the emblem remains legible at small sizes.

- `ios.png`: canonical square artwork, created with the built-in Imagegen tool in
  image-edit mode using the supplied logo as reference. iOS applies its own mask.
- `macos-template.svg`: deterministic platform container for the same artwork,
  with a rounded white tile, transparent outer margin and subtle shadow.
- `macos.png`: rendered 1024-pixel macOS master. The desktop PNGs and ICNS have
  actual transparent corners; the iOS catalog has fully opaque backgrounds.

Run `npm run icons` to regenerate the desktop assets and the tracked iOS catalog
in `src-tauri/icons/ios`. The script uses the project's installed Tauri CLI.
`npm run icons:sync` copies that catalog into an existing generated Xcode project.
The sync also runs before development and production frontend builds and from
`scripts/build-ios.sh`, preserving icons after Xcode project regeneration. It only
writes changed files, avoiding development rebuild loops. No iPhone installation
or signing is performed by these scripts.

The native configuration explicitly includes `icon.icns`, so macOS development
launches and packaged apps both use the rounded desktop icon.

## Imagegen prompt

```text
Use case: logo-brand. Asset type: production iPhone app icon source, exactly square 1024x1024. Use the supplied logo as the exact visual source. Extract ONLY its green tree/leaf emblem at the top, preserving its exact silhouette, number of lobes and curved white negative-space cuts. Do not redesign or stylize the emblem. Omit the blue lettering underneath entirely. Place the crisp flat original green emblem centered optically on a pure white (#FFFFFF) background. The emblem should occupy about 58 percent of the square width and 58 percent height, with balanced generous white space. Crisp smooth vector-like edges, flat original green near #00983A. This is the actual final icon artwork, not a device mockup or preview. Full-bleed opaque white square all the way into the four corners; NO rounded outer corners, no outer transparency, no inset tile, no frame, no drop shadow, no calendar, no letters, no text, no invented elements. Apple will mask this square automatically on iOS. Save as a high-quality PNG asset.
```

Imagegen returned a 1254-pixel source; Tauri resamples it to each required size,
including the 1024-pixel iOS marketing icon.

Platform references: [Apple app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
and [Tauri icon generation](https://v2.tauri.app/develop/icons/).
