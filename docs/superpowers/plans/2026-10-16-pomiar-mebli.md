# Pomiar mebli — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplikacja iOS (iPhone 14 Pro Max, LiDAR): zdjęcie + mapa głębi, punkty wskazywane na zamrożonym zdjęciu, wymiary z głębi LiDAR, eksport JPEG z wymiarami.

**Architecture:** SwiftUI, iOS 17+. Czysty moduł `MeasureEngine` (matematyka głębi, bez ARKit) + `Store` (pliki) + `Capture` (ARKit) + widoki. Projekt generowany z `project.yml` (XcodeGen). Budowanie i testy wyłącznie w GitHub Actions (macOS runner) — autor pracuje na Windowsie bez Maca; `.ipa` instalowany przez Sideloadly.

**Tech Stack:** Swift 5.9, SwiftUI, ARKit, CoreImage, XCTest, XcodeGen, GitHub Actions, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-10-16-pomiar-mebli-design.md`

## Global Constraints

- Platforma: iOS 17.0+, tylko iPhone (`TARGETED_DEVICE_FAMILY: "1"`), wymagany LiDAR (`sceneDepth`), UI tylko w pionie.
- Swift 5.9 (tryb języka Swift 5), brak zewnętrznych zależności SPM/CocoaPods.
- Jednostki: wymiary w milimetrach, etykieta `"<liczba całkowita> mm"` (np. `1280 mm`), brak pomiaru → `"—"`.
- Współrzędne pomiarów zawsze w układzie obrazu sensora, znormalizowane 0…1 (`NormalizedPoint`); obrót tylko przy wyświetlaniu.
- Głębia: `Float32` metry, pewność `UInt8` (2 = wysoka); tylko piksele o wysokiej pewności są brane do pomiaru.
- Wiarygodność: zielona / żółta / czerwona (`Reliability`); zakres roboczy 0,3–5 m.
- Repozytorium publiczne: `rozkrojeszczecinek1-gif/pomiar-mebli`, gałąź `main`.
- Teksty interfejsu po polsku.
- Brak Maca: **„uruchom testy” = push + `scripts/ci-wait.sh`** (patrz Task 1). Na lokalnym Windowsie nic się nie kompiluje.
- Każdy commit kończy się linią `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Dotknięcie punktu dokładnie na krawędzi/rogu obrazu (x=0, x=1, y=0, y=1) → bez crasha i bez fałszywego „żółtego” (Task 2).
2. Punkt na szkle/czerni (brak pikseli o wysokiej pewności) → pomiar „—”, czerwony, bez crasha (Task 2, Task 6).
3. Dwa identyczne punkty → 0 mm, bez dzielenia przez zero (Task 2).
4. Zdjęcie zrobione przy telefonie trzymanym poziomo lub do góry nogami → punkty trafiają w to samo miejsce obrazu po obrocie (Task 3).
5. Urządzenie bez LiDAR / symulator → komunikat zamiast crasha (Task 5).

---

### Task 1: Szkielet projektu, repozytorium i CI

**Files:**
- Create: `.gitignore`, `.gitattributes`, `project.yml`
- Create: `Sources/App/PomiarMebliApp.swift`, `Sources/App/RootView.swift`
- Create: `Tests/SmokeTests.swift`
- Create: `.github/workflows/ci.yml`, `scripts/ci-wait.sh`

**Interfaces:**
- Produces: schemat `PomiarMebli` (testy `PomiarMebliTests`, `@testable import PomiarMebli`), skrypt `scripts/ci-wait.sh` (blokuje do końca CI dla bieżącego commita, przy błędzie drukuje logi), artefakt CI `PomiarMebli-ipa`.

- [ ] **Step 1: Pliki konfiguracyjne**

`.gitignore`:
```
.DS_Store
build/
DerivedData/
*.xcodeproj
*.ipa
Payload/
```
`.gitattributes`:
```
* text=auto eol=lf
```
`project.yml`:
```yaml
name: PomiarMebli
options:
  bundleIdPrefix: pl.rozkroj
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  PomiarMebli:
    type: application
    platform: iOS
    sources: [Sources]
    info:
      path: Sources/Info.plist
      properties:
        CFBundleDisplayName: Pomiar mebli
        NSCameraUsageDescription: Aparat służy do robienia zdjęć z pomiarem głębi.
        UILaunchScreen: {}
        UIRequiredDeviceCapabilities: [arkit]
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.rozkroj.pomiarmebli
        TARGETED_DEVICE_FAMILY: "1"
    scheme:
      testTargets: [PomiarMebliTests]
  PomiarMebliTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies:
      - target: PomiarMebli
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: Minimalna aplikacja i test**

`Sources/App/PomiarMebliApp.swift`:
```swift
import SwiftUI

@main
struct PomiarMebliApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```
`Sources/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Pomiar mebli")
    }
}
```
`Tests/SmokeTests.swift`:
```swift
import XCTest
@testable import PomiarMebli

final class SmokeTests: XCTestCase {
    func testAppModuleLoads() {
        _ = RootView()
    }
}
```

- [ ] **Step 3: Workflow CI**

`.github/workflows/ci.yml`:
```yaml
name: ci
on:
  push:
  pull_request:
  workflow_dispatch:
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
      - name: Test
        run: |
          xcodebuild test -project PomiarMebli.xcodeproj -scheme PomiarMebli \
            -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
      - name: Build unsigned IPA
        run: |
          xcodebuild build -project PomiarMebli.xcodeproj -scheme PomiarMebli \
            -configuration Release -sdk iphoneos -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" -quiet
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/PomiarMebli.app Payload/
          zip -qr PomiarMebli.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: PomiarMebli-ipa
          path: PomiarMebli.ipa
```
`scripts/ci-wait.sh`:
```bash
#!/usr/bin/env bash
# Czeka na zakończenie CI dla bieżącego commita; przy błędzie drukuje logi.
set -uo pipefail
sha=$(git rev-parse HEAD)
id=""
for _ in $(seq 1 12); do
  id=$(gh run list --commit "$sha" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
  [ -n "$id" ] && break
  sleep 5
done
[ -z "$id" ] && { echo "Brak przebiegu CI dla $sha"; exit 2; }
if ! gh run watch "$id" --exit-status; then
  gh run view "$id" --log-failed | tail -150
  exit 1
fi
```

- [ ] **Step 4: Repozytorium publiczne i pierwszy push**

```bash
cd /e/pomiar-mebli
chmod +x scripts/ci-wait.sh
git add -A
git commit -m "Add project skeleton and CI

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
"/c/Program Files/GitHub CLI/gh.exe" repo create rozkrojeszczecinek1-gif/pomiar-mebli --public --source . --remote origin --push
```
(Jeśli `gh` jest już w PATH nowej sesji, wywołuj bez pełnej ścieżki.)

- [ ] **Step 5: Uruchom CI i napraw do zielonego**

Run: `bash scripts/ci-wait.sh`
Expected: PASS. Typowe poprawki: nazwa symulatora (`xcrun simctl list devices available` w kroku diagnostycznym → podmień `iPhone 16`), etykieta runnera (`macos-15` → `macos-latest`), ścieżka `.app`. Po każdej poprawce: commit + push + ponownie `ci-wait.sh`.

- [ ] **Step 6: Pobierz `.ipa` (kontrola potoku)**

Run: `gh run download <id> -n PomiarMebli-ipa -D /tmp/ipa && ls -l /tmp/ipa`
Expected: plik `PomiarMebli.ipa` > 0 B.

- [ ] **Step 7: Commit poprawek CI (jeśli były)** — komunikat `fix: CI ...`.

---

### Task 2: MeasureEngine (matematyka głębi)

**Files:**
- Create: `Sources/Core/Models.swift`, `Sources/Core/MeasureEngine.swift`
- Test: `Tests/MeasureEngineTests.swift`
- Modify: `docs/superpowers/specs/2026-10-16-pomiar-mebli-design.md` (sekcja 3: kryterium zgodności)

**Interfaces:**
- Produces:
  - `struct NormalizedPoint: Codable, Equatable { var x: Double; var y: Double }`
  - `struct CameraIntrinsics: Codable, Equatable { fx, fy, cx, cy: Double; imageWidth, imageHeight: Int }`
  - `enum Reliability: Int, Codable, Comparable { case green, yellow, red }`
  - `struct DepthMap: Equatable { width, height: Int; depth: [Float]; confidence: [UInt8]; static func uniform(width:height:depth:confidence:) -> DepthMap }`
  - `struct DepthSample: Equatable { depth: Float?; reliability: Reliability }`
  - `struct MeasurementResult: Equatable { millimeters: Double?; reliability: Reliability; var label: String }`
  - `MeasureEngine.sample(_:at:) -> DepthSample`, `.point3D(_:_:at:) -> (point: SIMD3<Float>, reliability: Reliability)?`, `.measure(_:_:from:to:) -> MeasurementResult`

- [ ] **Step 1: Napisz testy**

`Tests/MeasureEngineTests.swift`:
```swift
import XCTest
@testable import PomiarMebli

final class MeasureEngineTests: XCTestCase {
    // 1920x1440, f=1500 -> przy głębi 256x192: fx_d = 200, cx_d = 128, cy_d = 96
    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)
    func plane(_ z: Float) -> DepthMap { .uniform(width: 256, height: 192, depth: z) }
    func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }

    func testPlaneAtTwoMetersGives1280mm() {
        let r = MeasureEngine.measure(plane(2.0), k, from: p(0.25, 0.5), to: p(0.75, 0.5))
        XCTAssertEqual(r.millimeters!, 1280, accuracy: 0.5)
        XCTAssertEqual(r.reliability, .green)
        XCTAssertEqual(r.label, "1280 mm")
    }

    func testDifferentDepthsUse3DDistance() {
        var m = plane(2.0)
        for y in 0..<192 { for x in 128..<256 { m.depth[y * 256 + x] = 3.0 } }
        let r = MeasureEngine.measure(m, k, from: p(0.25, 0.5), to: p(0.75, 0.5))
        XCTAssertEqual(r.millimeters!, 1886.8, accuracy: 1.0)
    }

    func testIdenticalPointsGiveZero() {
        let r = MeasureEngine.measure(plane(2.0), k, from: p(0.4, 0.4), to: p(0.4, 0.4))
        XCTAssertEqual(r.millimeters!, 0, accuracy: 0.001)
        XCTAssertEqual(r.label, "0 mm")
    }

    func testCornersAndEdgesAreGreenAndDoNotCrash() {
        for (x, y) in [(0.0, 0.0), (1.0, 1.0), (0.0, 1.0), (1.0, 0.0), (0.5, 0.0), (1.0, 0.5)] {
            let s = MeasureEngine.sample(plane(2.0), at: p(x, y))
            XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001, "x=\(x) y=\(y)")
            XCTAssertEqual(s.reliability, .green, "x=\(x) y=\(y)")
        }
    }

    func testAllLowConfidenceIsRedAndNil() {
        let m = DepthMap.uniform(width: 256, height: 192, depth: 2.0, confidence: 0)
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertNil(s.depth)
        XCTAssertEqual(s.reliability, .red)
        let r = MeasureEngine.measure(m, k, from: p(0.2, 0.5), to: p(0.8, 0.5))
        XCTAssertNil(r.millimeters)
        XCTAssertEqual(r.reliability, .red)
        XCTAssertEqual(r.label, "—")
    }

    func testNaNAndZeroPixelsAreIgnored() {
        var m = plane(2.0)
        let c = 96 * 256 + 128
        m.depth[c] = .nan
        m.depth[c + 1] = 0
        m.depth[c - 1] = -1
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001)
    }

    func testLowConfidenceOutliersDoNotAffectMedian() {
        var m = plane(2.0)
        for dy in -1...1 { for dx in -1...1 {
            let i = (96 + dy) * 256 + (128 + dx)
            m.depth[i] = 0.5; m.confidence[i] = 0
        } }
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001)
    }

    func testFewValidPixelsGiveYellowButStillMeasure() {
        var m = DepthMap.uniform(width: 256, height: 192, depth: 2.0, confidence: 0)
        let c = 96 * 256 + 128
        for i in [c, c + 1, c - 1] { m.confidence[i] = 2 }   // 3 z 25 = 12% < 30%, ale 7x7 ma 3 ważne
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.depth!, 2.0, accuracy: 0.001)
        XCTAssertEqual(s.reliability, .yellow)
    }

    func testStepEdgeIsYellow() {
        var m = plane(1.0)
        for y in 0..<192 { for x in 129..<256 { m.depth[y * 256 + x] = 3.0 } }
        // okno 5x5 wokół x=128: kolumny 126..130 -> 3 kolumny 1 m, 2 kolumny 3 m (60/40)
        let s = MeasureEngine.sample(m, at: p(0.5, 0.5))
        XCTAssertEqual(s.reliability, .yellow)
    }

    func testOutOfRangeIsYellow() {
        XCTAssertEqual(MeasureEngine.sample(plane(6.0), at: p(0.5, 0.5)).reliability, .yellow)
        XCTAssertEqual(MeasureEngine.sample(plane(0.2), at: p(0.5, 0.5)).reliability, .yellow)
    }

    func testMeasurementReliabilityIsWorstOfTwoPoints() {
        var m = plane(2.0)
        for i in 0..<(192 * 256) where (i % 256) < 128 { m.confidence[i] = 0 }
        let r = MeasureEngine.measure(m, k, from: p(0.1, 0.5), to: p(0.9, 0.5))
        XCTAssertNil(r.millimeters)           // lewy punkt bez ważnych pikseli
        XCTAssertEqual(r.reliability, .red)
    }
}
```

- [ ] **Step 2: Wypchnij same testy i potwierdź czerwone CI**

Run: `git add -A && git commit -m "test: MeasureEngine tests" && git push && bash scripts/ci-wait.sh`
Expected: FAIL (kompilacja: brak `MeasureEngine`, `DepthMap` itd.).

- [ ] **Step 3: Implementacja**

`Sources/Core/Models.swift`:
```swift
import Foundation

struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct CameraIntrinsics: Codable, Equatable {
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double
    var imageWidth: Int
    var imageHeight: Int
}

enum Reliability: Int, Codable, Comparable {
    case green = 0, yellow = 1, red = 2
    static func < (l: Reliability, r: Reliability) -> Bool { l.rawValue < r.rawValue }
}

struct DepthMap: Equatable {
    let width: Int
    let height: Int
    var depth: [Float]
    var confidence: [UInt8]

    static func uniform(width: Int, height: Int, depth: Float, confidence: UInt8 = 2) -> DepthMap {
        DepthMap(width: width, height: height,
                 depth: [Float](repeating: depth, count: width * height),
                 confidence: [UInt8](repeating: confidence, count: width * height))
    }
}
```
`Sources/Core/MeasureEngine.swift`:
```swift
import Foundation
import simd

struct DepthSample: Equatable {
    var depth: Float?
    var reliability: Reliability
}

struct MeasurementResult: Equatable {
    var millimeters: Double?
    var reliability: Reliability

    var label: String {
        guard let mm = millimeters else { return "—" }
        return "\(Int(mm.rounded())) mm"
    }
}

enum MeasureEngine {
    static let highConfidence: UInt8 = 2
    static let minRange: Float = 0.3
    static let maxRange: Float = 5.0

    static func sample(_ map: DepthMap, at p: NormalizedPoint) -> DepthSample {
        let cx = clamp(Int((p.x * Double(map.width)).rounded(.down)), map.width)
        let cy = clamp(Int((p.y * Double(map.height)).rounded(.down)), map.height)

        let small = window(map, cx, cy, radius: 2)
        if small.total > 0, Double(small.values.count) / Double(small.total) >= 0.3 {
            let med = median(small.values)
            let share = Double(small.values.count) / Double(small.total)
            let agree = Double(small.values.filter { abs($0 - med) <= 0.02 * med }.count)
                / Double(small.values.count)
            let inRange = med >= minRange && med <= maxRange
            let solid = share >= 0.6 && agree >= 0.8
            return DepthSample(depth: med, reliability: (inRange && solid) ? .green : .yellow)
        }
        let large = window(map, cx, cy, radius: 3)
        if large.values.isEmpty { return DepthSample(depth: nil, reliability: .red) }
        return DepthSample(depth: median(large.values), reliability: .yellow)
    }

    static func point3D(_ map: DepthMap, _ k: CameraIntrinsics, at p: NormalizedPoint)
        -> (point: SIMD3<Float>, reliability: Reliability)? {
        let s = sample(map, at: p)
        guard let z = s.depth else { return nil }
        let sx = Double(map.width) / Double(k.imageWidth)
        let sy = Double(map.height) / Double(k.imageHeight)
        let u = p.x * Double(map.width)
        let v = p.y * Double(map.height)
        let x = (u - k.cx * sx) * Double(z) / (k.fx * sx)
        let y = (v - k.cy * sy) * Double(z) / (k.fy * sy)
        return (SIMD3<Float>(Float(x), Float(y), z), s.reliability)
    }

    static func measure(_ map: DepthMap, _ k: CameraIntrinsics,
                        from a: NormalizedPoint, to b: NormalizedPoint) -> MeasurementResult {
        guard let pa = point3D(map, k, at: a), let pb = point3D(map, k, at: b) else {
            return MeasurementResult(millimeters: nil, reliability: .red)
        }
        let mm = Double(simd_distance(pa.point, pb.point)) * 1000
        return MeasurementResult(millimeters: mm, reliability: max(pa.reliability, pb.reliability))
    }

    // MARK: - helpers

    private static func clamp(_ i: Int, _ n: Int) -> Int { min(max(i, 0), n - 1) }

    private static func window(_ m: DepthMap, _ cx: Int, _ cy: Int, radius r: Int)
        -> (values: [Float], total: Int) {
        var out: [Float] = []
        var total = 0
        for y in max(0, cy - r)...min(m.height - 1, cy + r) {
            for x in max(0, cx - r)...min(m.width - 1, cx + r) {
                total += 1
                let i = y * m.width + x
                let d = m.depth[i]
                if m.confidence[i] == highConfidence, d.isFinite, d > 0 { out.append(d) }
            }
        }
        return (out, total)
    }

    private static func median(_ v: [Float]) -> Float {
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
```

- [ ] **Step 4: Zaktualizuj spec (sekcja 3)**

W specyfikacji zamień zdanie o wiarygodności na: „zielona gdy ≥ 60% pikseli okna ważnych i ≥ 80% ważnych pikseli mieści się w ±2% mediany; poza zakresem 0,3–5 m — żółta.” (zastępuje kryterium MAD — odporne na krawędzie między planami).

- [ ] **Step 5: Push i zielone CI**

Run: `git add -A && git commit -m "feat: MeasureEngine" && git push && bash scripts/ci-wait.sh`
Expected: PASS. Jeśli test progu zawodzi (np. `testStepEdgeIsYellow`), popraw dane testowe lub próg w kodzie i w spec, nie osłabiaj asercji.

---

### Task 3: Geometria obrazu i orientacja

**Files:**
- Create: `Sources/Core/Geometry.swift`
- Test: `Tests/GeometryTests.swift`

**Interfaces:**
- Consumes: `NormalizedPoint` (Task 2).
- Produces:
  - `enum ImageOrientation: Int, Codable { case up = 0, down, left, right }`
  - `enum SensorGeometry { static func displayedSize(sensorWidth:sensorHeight:orientation:) -> (width: Double, height: Double); static func toDisplay(_:_:) -> NormalizedPoint; static func toSensor(_:_:) -> NormalizedPoint; static func imageOrientation(for: UIDeviceOrientation) -> ImageOrientation }`
  - `struct ImageLayout { let rect: CGRect; init(container: CGSize, displayed: CGSize); func viewPoint(_ d: NormalizedPoint) -> CGPoint; func displayPoint(_ v: CGPoint) -> NormalizedPoint }`
  - `extension ImageOrientation { var uiOrientation: UIImage.Orientation }`

- [ ] **Step 1: Testy**

`Tests/GeometryTests.swift`:
```swift
import XCTest
import UIKit
@testable import PomiarMebli

final class GeometryTests: XCTestCase {
    func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }
    func assertEqual(_ a: NormalizedPoint, _ b: NormalizedPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
    }

    func testRightRotatesCornersClockwise() {
        assertEqual(SensorGeometry.toDisplay(p(0, 0), .right), p(1, 0))
        assertEqual(SensorGeometry.toDisplay(p(1, 0), .right), p(1, 1))
        assertEqual(SensorGeometry.toDisplay(p(1, 1), .right), p(0, 1))
        assertEqual(SensorGeometry.toDisplay(p(0, 1), .right), p(0, 0))
    }

    func testLeftRotatesCornersCounterClockwise() {
        assertEqual(SensorGeometry.toDisplay(p(0, 0), .left), p(0, 1))
        assertEqual(SensorGeometry.toDisplay(p(1, 0), .left), p(0, 0))
    }

    func testDownIsPointReflection() {
        assertEqual(SensorGeometry.toDisplay(p(0.2, 0.7), .down), p(0.8, 0.3))
    }

    func testRoundTripForAllOrientations() {
        for o in [ImageOrientation.up, .down, .left, .right] {
            for pt in [p(0, 0), p(1, 1), p(0.3, 0.8), p(0.5, 0.5), p(1, 0)] {
                assertEqual(SensorGeometry.toSensor(SensorGeometry.toDisplay(pt, o), o), pt)
            }
        }
    }

    func testDisplayedSizeSwapsForSideways() {
        XCTAssertEqual(SensorGeometry.displayedSize(sensorWidth: 1920, sensorHeight: 1440, orientation: .right).width, 1440)
        XCTAssertEqual(SensorGeometry.displayedSize(sensorWidth: 1920, sensorHeight: 1440, orientation: .up).width, 1920)
    }

    func testDeviceOrientationMapping() {
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .portrait), .right)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .portraitUpsideDown), .left)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .landscapeLeft), .up)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .landscapeRight), .down)
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .faceUp), .right)   // nieznana -> pion
        XCTAssertEqual(SensorGeometry.imageOrientation(for: .unknown), .right)
    }

    func testLayoutFitsAndCenters() {
        let l = ImageLayout(container: CGSize(width: 400, height: 800), displayed: CGSize(width: 300, height: 400))
        XCTAssertEqual(l.rect, CGRect(x: 0, y: 100, width: 400, height: 600))
        let v = l.viewPoint(p(0.5, 0.5))
        XCTAssertEqual(v.x, 200, accuracy: 1e-9)
        XCTAssertEqual(v.y, 400, accuracy: 1e-9)
        assertEqual(l.displayPoint(CGPoint(x: 200, y: 400)), p(0.5, 0.5))
    }

    func testDisplayPointIsClampedOutsideImage() {
        let l = ImageLayout(container: CGSize(width: 400, height: 800), displayed: CGSize(width: 300, height: 400))
        assertEqual(l.displayPoint(CGPoint(x: -50, y: 0)), p(0, 0))
        assertEqual(l.displayPoint(CGPoint(x: 999, y: 999)), p(1, 1))
    }

    func testZeroSizesDoNotCrash() {
        let l = ImageLayout(container: .zero, displayed: CGSize(width: 10, height: 10))
        XCTAssertEqual(l.rect, .zero)
        assertEqual(l.displayPoint(CGPoint(x: 5, y: 5)), p(0, 0))
    }
}
```

- [ ] **Step 2: Implementacja**

`Sources/Core/Geometry.swift`:
```swift
import UIKit

/// Jak obrócić obraz sensora (landscape), żeby wyświetlić go „do góry nogami we właściwą stronę”.
enum ImageOrientation: Int, Codable {
    case up = 0, down, left, right

    var uiOrientation: UIImage.Orientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

enum SensorGeometry {
    static func displayedSize(sensorWidth w: Double, sensorHeight h: Double,
                              orientation o: ImageOrientation) -> (width: Double, height: Double) {
        switch o {
        case .up, .down: return (w, h)
        case .left, .right: return (h, w)
        }
    }

    static func toDisplay(_ p: NormalizedPoint, _ o: ImageOrientation) -> NormalizedPoint {
        switch o {
        case .up: return p
        case .down: return NormalizedPoint(x: 1 - p.x, y: 1 - p.y)
        case .right: return NormalizedPoint(x: 1 - p.y, y: p.x)
        case .left: return NormalizedPoint(x: p.y, y: 1 - p.x)
        }
    }

    static func toSensor(_ d: NormalizedPoint, _ o: ImageOrientation) -> NormalizedPoint {
        switch o {
        case .up: return d
        case .down: return NormalizedPoint(x: 1 - d.x, y: 1 - d.y)
        case .right: return NormalizedPoint(x: d.y, y: 1 - d.x)
        case .left: return NormalizedPoint(x: 1 - d.y, y: d.x)
        }
    }

    /// ARKit zwraca obraz w orientacji landscape (sensor). Portret = obrót o 90° w prawo.
    static func imageOrientation(for device: UIDeviceOrientation) -> ImageOrientation {
        switch device {
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }
}

/// Położenie obrazu (aspect-fit) w widoku i konwersja punktów.
struct ImageLayout: Equatable {
    let rect: CGRect

    init(container: CGSize, displayed: CGSize) {
        guard container.width > 0, container.height > 0, displayed.width > 0, displayed.height > 0 else {
            rect = .zero
            return
        }
        let s = min(container.width / displayed.width, container.height / displayed.height)
        let w = displayed.width * s
        let h = displayed.height * s
        rect = CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    func viewPoint(_ d: NormalizedPoint) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(d.x) * rect.width, y: rect.minY + CGFloat(d.y) * rect.height)
    }

    func displayPoint(_ v: CGPoint) -> NormalizedPoint {
        guard rect.width > 0, rect.height > 0 else { return NormalizedPoint(x: 0, y: 0) }
        let x = min(max(Double((v.x - rect.minX) / rect.width), 0), 1)
        let y = min(max(Double((v.y - rect.minY) / rect.height), 0), 1)
        return NormalizedPoint(x: x, y: y)
    }
}
```

- [ ] **Step 3: Push, CI zielone**

Run: `git add -A && git commit -m "feat: orientation and layout geometry" && git push && bash scripts/ci-wait.sh`
Expected: PASS.

---

### Task 4: Modele zdjęcia i Store

**Files:**
- Create: `Sources/Core/ShotModels.swift`, `Sources/Core/ShotStore.swift`
- Test: `Tests/ShotStoreTests.swift`

**Interfaces:**
- Consumes: `NormalizedPoint`, `CameraIntrinsics`, `DepthMap`, `ImageOrientation`.
- Produces:
  - `struct Measurement: Codable, Identifiable, Equatable { var id: UUID; var a: NormalizedPoint; var b: NormalizedPoint; init(id: UUID = UUID(), a:, b:) }`
  - `struct ShotMeta: Codable, Identifiable, Equatable { id: UUID; name: String; createdAt: Date; intrinsics: CameraIntrinsics; depthWidth: Int; depthHeight: Int; orientation: ImageOrientation; measurements: [Measurement] }`
  - `struct CapturedShot { jpeg: Data; depth: DepthMap; intrinsics: CameraIntrinsics; orientation: ImageOrientation }`
  - `DepthMap.encoded() -> Data`, `DepthMap.init?(data:width:height:)`
  - `final class ShotStore { init(root: URL); static func defaultRoot() -> URL; func save(_ shot: CapturedShot, name: String, now: Date) throws -> ShotMeta; func list() -> [ShotMeta]; func update(_ meta: ShotMeta) throws; func loadDepth(_ meta: ShotMeta) -> DepthMap?; func imageURL(for id: UUID) -> URL; func delete(id: UUID) }`

- [ ] **Step 1: Testy**

`Tests/ShotStoreTests.swift`:
```swift
import XCTest
@testable import PomiarMebli

final class ShotStoreTests: XCTestCase {
    var root: URL!
    var store: ShotStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID().uuidString)")
        store = ShotStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)
    func shot() -> CapturedShot {
        var d = DepthMap.uniform(width: 4, height: 3, depth: 1.5)
        d.depth[5] = 2.25; d.confidence[7] = 0
        return CapturedShot(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), depth: d, intrinsics: k, orientation: .right)
    }

    func testDepthMapEncodeDecodeRoundTrip() {
        let d = shot().depth
        let back = DepthMap(data: d.encoded(), width: 4, height: 3)
        XCTAssertEqual(back, d)
    }

    func testDepthMapDecodeRejectsWrongSize() {
        XCTAssertNil(DepthMap(data: Data(count: 10), width: 4, height: 3))
        XCTAssertNil(DepthMap(data: Data(), width: 0, height: 0))
    }

    func testSaveListLoad() throws {
        let meta = try store.save(shot(), name: "Kuchnia", now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(store.list(), [meta])
        XCTAssertEqual(store.loadDepth(meta), shot().depth)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: meta.id)), Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(meta.orientation, .right)
        XCTAssertEqual(meta.depthWidth, 4)
    }

    func testListIsNewestFirst() throws {
        let a = try store.save(shot(), name: "A", now: Date(timeIntervalSince1970: 1_000))
        let b = try store.save(shot(), name: "B", now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(store.list().map(\.id), [b.id, a.id])
    }

    func testUpdatePersistsMeasurements() throws {
        var meta = try store.save(shot(), name: "X", now: Date())
        meta.measurements.append(Measurement(a: NormalizedPoint(x: 0.1, y: 0.2), b: NormalizedPoint(x: 0.9, y: 0.8)))
        meta.name = "Nowa nazwa"
        try store.update(meta)
        XCTAssertEqual(store.list().first, meta)
    }

    func testDeleteRemovesFiles() throws {
        let meta = try store.save(shot(), name: "X", now: Date())
        store.delete(id: meta.id)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: meta.id).path))
    }

    func testCorruptMetaIsSkippedAndMissingDepthIsNil() throws {
        let good = try store.save(shot(), name: "OK", now: Date())
        let bad = try store.save(shot(), name: "BAD", now: Date())
        try Data("nie json".utf8).write(to: root.appendingPathComponent(bad.id.uuidString).appendingPathComponent("meta.json"))
        XCTAssertEqual(store.list().map(\.id), [good.id])
        try FileManager.default.removeItem(at: root.appendingPathComponent(good.id.uuidString).appendingPathComponent("depth.bin"))
        XCTAssertNil(store.loadDepth(good))
    }
}
```

- [ ] **Step 2: Implementacja**

`Sources/Core/ShotModels.swift`:
```swift
import Foundation

struct Measurement: Codable, Identifiable, Equatable {
    var id: UUID
    var a: NormalizedPoint
    var b: NormalizedPoint

    init(id: UUID = UUID(), a: NormalizedPoint, b: NormalizedPoint) {
        self.id = id
        self.a = a
        self.b = b
    }
}

struct ShotMeta: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var intrinsics: CameraIntrinsics
    var depthWidth: Int
    var depthHeight: Int
    var orientation: ImageOrientation
    var measurements: [Measurement]
}

struct CapturedShot {
    var jpeg: Data
    var depth: DepthMap
    var intrinsics: CameraIntrinsics
    var orientation: ImageOrientation
}

extension DepthMap {
    /// Float32 (little-endian, wiersz po wierszu), potem UInt8 pewności.
    func encoded() -> Data {
        var data = depth.withUnsafeBufferPointer { Data(buffer: $0) }
        data.append(contentsOf: confidence)
        return data
    }

    init?(data: Data, width: Int, height: Int) {
        let n = width * height
        guard width > 0, height > 0, data.count == n * 4 + n else { return nil }
        var floats = [Float](repeating: 0, count: n)
        floats.withUnsafeMutableBytes { _ = data.copyBytes(to: $0, from: 0..<(n * 4)) }
        let conf = [UInt8](data.subdata(in: (n * 4)..<data.count))
        self.init(width: width, height: height, depth: floats, confidence: conf)
    }
}
```
`Sources/Core/ShotStore.swift`:
```swift
import Foundation

final class ShotStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shots", isDirectory: true)
    }

    private func dir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func imageURL(for id: UUID) -> URL { dir(id).appendingPathComponent("foto.jpg") }
    private func depthURL(_ id: UUID) -> URL { dir(id).appendingPathComponent("depth.bin") }
    private func metaURL(_ id: UUID) -> URL { dir(id).appendingPathComponent("meta.json") }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func save(_ shot: CapturedShot, name: String, now: Date = Date()) throws -> ShotMeta {
        let meta = ShotMeta(id: UUID(), name: name, createdAt: now, intrinsics: shot.intrinsics,
                            depthWidth: shot.depth.width, depthHeight: shot.depth.height,
                            orientation: shot.orientation, measurements: [])
        try fm.createDirectory(at: dir(meta.id), withIntermediateDirectories: true)
        try shot.jpeg.write(to: imageURL(for: meta.id), options: .atomic)
        try shot.depth.encoded().write(to: depthURL(meta.id), options: .atomic)
        try encoder.encode(meta).write(to: metaURL(meta.id), options: .atomic)
        return meta
    }

    func update(_ meta: ShotMeta) throws {
        try encoder.encode(meta).write(to: metaURL(meta.id), options: .atomic)
    }

    func list() -> [ShotMeta] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { d -> ShotMeta? in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("meta.json")) else { return nil }
            return try? decoder.decode(ShotMeta.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func loadDepth(_ meta: ShotMeta) -> DepthMap? {
        guard let data = try? Data(contentsOf: depthURL(meta.id)) else { return nil }
        return DepthMap(data: data, width: meta.depthWidth, height: meta.depthHeight)
    }

    func delete(id: UUID) {
        try? fm.removeItem(at: dir(id))
    }
}
```

- [ ] **Step 3: Push, CI zielone**

Run: `git add -A && git commit -m "feat: shot models and store" && git push && bash scripts/ci-wait.sh`
Expected: PASS.

---

### Task 5: Przechwytywanie (ARKit)

**Files:**
- Create: `Sources/Capture/DepthExtraction.swift`, `Sources/Capture/CaptureController.swift`, `Sources/Capture/CaptureView.swift`
- Test: `Tests/DepthExtractionTests.swift`

**Interfaces:**
- Consumes: `DepthMap`, `CapturedShot`, `CameraIntrinsics`, `SensorGeometry.imageOrientation(for:)`.
- Produces:
  - `enum DepthExtraction { static func depthMap(depth: CVPixelBuffer, confidence: CVPixelBuffer) -> DepthMap? }`
  - `final class CaptureController: ObservableObject { static var isSupported: Bool; func start(session: ARSession); func stop(); func snap() -> CapturedShot? }`
  - `struct CaptureView: View { init(onCancel: @escaping () -> Void, onCaptured: @escaping (CapturedShot) -> Void) }`

- [ ] **Step 1: Testy**

`Tests/DepthExtractionTests.swift`:
```swift
import XCTest
import CoreVideo
@testable import PomiarMebli

final class DepthExtractionTests: XCTestCase {
    func makeBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary   // wymusza padding wierszy
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, format, attrs, &pb), kCVReturnSuccess)
        return pb!
    }

    func testExtractsValuesIgnoringRowPadding() {
        let d = makeBuffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent32Float)
        let c = makeBuffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent8)
        CVPixelBufferLockBaseAddress(d, []); CVPixelBufferLockBaseAddress(c, [])
        let ds = CVPixelBufferGetBytesPerRow(d), cs = CVPixelBufferGetBytesPerRow(c)
        for y in 0..<3 { for x in 0..<5 {
            d_row(d, y, ds)[x] = Float(y * 10 + x)
            c_row(c, y, cs)[x] = UInt8(x % 3)
        } }
        CVPixelBufferUnlockBaseAddress(d, []); CVPixelBufferUnlockBaseAddress(c, [])

        let m = DepthExtraction.depthMap(depth: d, confidence: c)!
        XCTAssertEqual(m.width, 5); XCTAssertEqual(m.height, 3)
        XCTAssertEqual(m.depth[2 * 5 + 4], 24)
        XCTAssertEqual(m.depth[1 * 5 + 2], 12)
        XCTAssertEqual(m.confidence[4], 1)
    }

    func testMismatchedSizesReturnNil() {
        let d = makeBuffer(width: 5, height: 3, format: kCVPixelFormatType_OneComponent32Float)
        let c = makeBuffer(width: 4, height: 3, format: kCVPixelFormatType_OneComponent8)
        XCTAssertNil(DepthExtraction.depthMap(depth: d, confidence: c))
    }

    func testSimulatorHasNoLiDAR() {
        // Testy działają na symulatorze: widok kamery musi pokazać komunikat, a nie uruchamiać sesji.
        XCTAssertFalse(CaptureController.isSupported)
    }

    private func d_row(_ b: CVPixelBuffer, _ y: Int, _ stride: Int) -> UnsafeMutablePointer<Float> {
        CVPixelBufferGetBaseAddress(b)!.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
    }
    private func c_row(_ b: CVPixelBuffer, _ y: Int, _ stride: Int) -> UnsafeMutablePointer<UInt8> {
        CVPixelBufferGetBaseAddress(b)!.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
    }
}
```

- [ ] **Step 2: Implementacja**

`Sources/Capture/DepthExtraction.swift`:
```swift
import CoreVideo

enum DepthExtraction {
    /// Kopiuje bufory głębi i pewności do tablic (uwzględnia padding wierszy).
    static func depthMap(depth: CVPixelBuffer, confidence: CVPixelBuffer) -> DepthMap? {
        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        guard w > 0, h > 0,
              CVPixelBufferGetWidth(confidence) == w,
              CVPixelBufferGetHeight(confidence) == h else { return nil }

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depth, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }
        guard let dBase = CVPixelBufferGetBaseAddress(depth),
              let cBase = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        let dStride = CVPixelBufferGetBytesPerRow(depth)
        let cStride = CVPixelBufferGetBytesPerRow(confidence)

        var d = [Float](repeating: 0, count: w * h)
        var c = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let dRow = dBase.advanced(by: y * dStride).assumingMemoryBound(to: Float.self)
            let cRow = cBase.advanced(by: y * cStride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                d[y * w + x] = dRow[x]
                c[y * w + x] = cRow[x]
            }
        }
        return DepthMap(width: w, height: h, depth: d, confidence: c)
    }
}
```
`Sources/Capture/CaptureController.swift`:
```swift
import ARKit
import CoreImage
import ImageIO
import UIKit

@MainActor
final class CaptureController: ObservableObject {
    private var session: ARSession?
    private let ciContext = CIContext()

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    func start(session: ARSession) {
        guard Self.isSupported else { return }
        self.session = session
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        session.run(config)
    }

    func stop() {
        session?.pause()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func snap() -> CapturedShot? {
        guard let frame = session?.currentFrame,
              let sceneDepth = frame.sceneDepth,
              let confidence = sceneDepth.confidenceMap,
              let depth = DepthExtraction.depthMap(depth: sceneDepth.depthMap, confidence: confidence),
              let jpeg = ciContext.jpegRepresentation(
                of: CIImage(cvPixelBuffer: frame.capturedImage),
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92])
        else { return nil }

        let k = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let intrinsics = CameraIntrinsics(fx: Double(k[0][0]), fy: Double(k[1][1]),
                                          cx: Double(k[2][0]), cy: Double(k[2][1]),
                                          imageWidth: Int(res.width), imageHeight: Int(res.height))
        let orientation = SensorGeometry.imageOrientation(for: UIDevice.current.orientation)
        return CapturedShot(jpeg: jpeg, depth: depth, intrinsics: intrinsics, orientation: orientation)
    }
}
```
`Sources/Capture/CaptureView.swift`:
```swift
import SwiftUI
import ARKit
import RealityKit

struct CaptureView: View {
    let onCancel: () -> Void
    let onCaptured: (CapturedShot) -> Void

    @StateObject private var controller = CaptureController()
    @State private var failed = false

    var body: some View {
        ZStack {
            if CaptureController.isSupported {
                ARCameraView(controller: controller).ignoresSafeArea()
                VStack {
                    HStack {
                        Button("Anuluj", action: onCancel)
                            .padding(10).background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }.padding()
                    Spacer()
                    if failed {
                        Text("Nie udało się zapisać klatki z głębią — spróbuj jeszcze raz.")
                            .font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule())
                    }
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4)
                            .background(Circle().fill(.white.opacity(0.85)).padding(6))
                            .frame(width: 76, height: 76)
                    }
                    .padding(.bottom, 28)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("To urządzenie nie ma skanera LiDAR.\nPotrzebny jest iPhone Pro (12 Pro lub nowszy).")
                        .multilineTextAlignment(.center)
                    Button("Wróć", action: onCancel)
                }.padding()
            }
        }
    }

    private func shoot() {
        if let shot = controller.snap() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            controller.stop()
            onCaptured(shot)
        } else {
            failed = true
        }
    }
}

private struct ARCameraView: UIViewRepresentable {
    let controller: CaptureController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        controller.start(session: view.session)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
    }
}
```

- [ ] **Step 3: Push, CI zielone**

Run: `git add -A && git commit -m "feat: ARKit capture" && git push && bash scripts/ci-wait.sh`
Expected: PASS (kompilacja ARKit/RealityKit na symulatorze; test `testSimulatorHasNoLiDAR` zakłada symulator).

---

### Task 6: Logika ekranu pomiarów (MeasureViewModel)

**Files:**
- Create: `Sources/Measure/MeasureViewModel.swift`
- Test: `Tests/MeasureViewModelTests.swift`

**Interfaces:**
- Consumes: `ShotMeta`, `Measurement`, `DepthMap`, `ShotStore`, `MeasureEngine`, `MeasurementResult`.
- Produces:
  - `enum DragTarget: Equatable { case a(UUID), b(UUID), pending }`
  - `@MainActor final class MeasureViewModel: ObservableObject { @Published private(set) var meta: ShotMeta; @Published private(set) var pendingA: NormalizedPoint?; init(meta:depth:store:); func result(for: Measurement) -> MeasurementResult; func hit(at: CGPoint, radius: CGFloat, project: (NormalizedPoint) -> CGPoint) -> DragTarget?; func move(_: DragTarget, to: NormalizedPoint); func place(at: NormalizedPoint); func commit(); func delete(_ id: UUID); func rename(_ name: String); func cancelPending() }`

- [ ] **Step 1: Testy**

`Tests/MeasureViewModelTests.swift`:
```swift
import XCTest
@testable import PomiarMebli

@MainActor
final class MeasureViewModelTests: XCTestCase {
    var root: URL!
    var store: ShotStore!
    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString)")
        store = ShotStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func p(_ x: Double, _ y: Double) -> NormalizedPoint { NormalizedPoint(x: x, y: y) }

    func makeVM(depth: DepthMap = .uniform(width: 256, height: 192, depth: 2.0)) throws -> MeasureViewModel {
        let shot = CapturedShot(jpeg: Data([1]), depth: depth, intrinsics: k, orientation: .right)
        let meta = try store.save(shot, name: "T", now: Date())
        return MeasureViewModel(meta: meta, depth: depth, store: store)
    }

    func testTwoPlacesCreateMeasurementAndThirdStartsNext() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5))
        XCTAssertEqual(vm.pendingA, p(0.25, 0.5))
        XCTAssertTrue(vm.meta.measurements.isEmpty)
        vm.place(at: p(0.75, 0.5))
        XCTAssertNil(vm.pendingA)
        XCTAssertEqual(vm.meta.measurements.count, 1)
        XCTAssertEqual(vm.result(for: vm.meta.measurements[0]).label, "1280 mm")
        vm.place(at: p(0.1, 0.1))
        XCTAssertEqual(vm.pendingA, p(0.1, 0.1))
    }

    func testPlacePersistsToStore() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        XCTAssertEqual(store.list().first?.measurements.count, 1)
    }

    func testHitFindsNearestEndpointWithinRadius() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        let id = vm.meta.measurements[0].id
        let project: (NormalizedPoint) -> CGPoint = { CGPoint(x: $0.x * 400, y: $0.y * 300) }
        XCTAssertEqual(vm.hit(at: CGPoint(x: 105, y: 152), radius: 24, project: project), .a(id))
        XCTAssertEqual(vm.hit(at: CGPoint(x: 296, y: 148), radius: 24, project: project), .b(id))
        XCTAssertNil(vm.hit(at: CGPoint(x: 200, y: 150), radius: 24, project: project))
    }

    func testHitFindsPendingPoint() throws {
        let vm = try makeVM()
        vm.place(at: p(0.5, 0.5))
        let project: (NormalizedPoint) -> CGPoint = { CGPoint(x: $0.x * 400, y: $0.y * 300) }
        XCTAssertEqual(vm.hit(at: CGPoint(x: 200, y: 150), radius: 24, project: project), .pending)
    }

    func testMoveChangesResultAndCommitPersists() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        let m = vm.meta.measurements[0]
        vm.move(.b(m.id), to: p(0.50, 0.5))
        XCTAssertEqual(vm.result(for: vm.meta.measurements[0]).label, "640 mm")
        vm.commit()
        XCTAssertEqual(store.list().first?.measurements[0].b, p(0.5, 0.5))
    }

    func testDeleteAndRename() throws {
        let vm = try makeVM()
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        vm.rename("Szafa")
        vm.delete(vm.meta.measurements[0].id)
        XCTAssertTrue(vm.meta.measurements.isEmpty)
        XCTAssertEqual(store.list().first?.name, "Szafa")
        XCTAssertEqual(store.list().first?.measurements.count, 0)
    }

    func testPointWithoutValidDepthGivesDashAndDoesNotCrash() throws {
        let vm = try makeVM(depth: .uniform(width: 256, height: 192, depth: 2.0, confidence: 0))
        vm.place(at: p(0.25, 0.5)); vm.place(at: p(0.75, 0.5))
        let r = vm.result(for: vm.meta.measurements[0])
        XCTAssertEqual(r.label, "—")
        XCTAssertEqual(r.reliability, .red)
    }

    func testCancelPending() throws {
        let vm = try makeVM()
        vm.place(at: p(0.5, 0.5)); vm.cancelPending()
        XCTAssertNil(vm.pendingA)
    }
}
```

- [ ] **Step 2: Implementacja**

`Sources/Measure/MeasureViewModel.swift`:
```swift
import Foundation
import CoreGraphics

enum DragTarget: Equatable {
    case a(UUID)
    case b(UUID)
    case pending
}

@MainActor
final class MeasureViewModel: ObservableObject {
    @Published private(set) var meta: ShotMeta
    @Published private(set) var pendingA: NormalizedPoint?
    let depth: DepthMap
    private let store: ShotStore

    init(meta: ShotMeta, depth: DepthMap, store: ShotStore) {
        self.meta = meta
        self.depth = depth
        self.store = store
    }

    func result(for m: Measurement) -> MeasurementResult {
        MeasureEngine.measure(depth, meta.intrinsics, from: m.a, to: m.b)
    }

    func hit(at point: CGPoint, radius: CGFloat,
             project: (NormalizedPoint) -> CGPoint) -> DragTarget? {
        var best: (target: DragTarget, dist: CGFloat)?
        func consider(_ t: DragTarget, _ n: NormalizedPoint) {
            let q = project(n)
            let d = hypot(q.x - point.x, q.y - point.y)
            if d <= radius, d < (best?.dist ?? .infinity) { best = (t, d) }
        }
        if let a = pendingA { consider(.pending, a) }
        for m in meta.measurements {
            consider(.a(m.id), m.a)
            consider(.b(m.id), m.b)
        }
        return best?.target
    }

    func move(_ target: DragTarget, to p: NormalizedPoint) {
        switch target {
        case .pending: pendingA = p
        case .a(let id): mutate(id) { $0.a = p }
        case .b(let id): mutate(id) { $0.b = p }
        }
    }

    func place(at p: NormalizedPoint) {
        if let a = pendingA {
            meta.measurements.append(Measurement(a: a, b: p))
            pendingA = nil
            persist()
        } else {
            pendingA = p
        }
    }

    func commit() { persist() }

    func delete(_ id: UUID) {
        meta.measurements.removeAll { $0.id == id }
        persist()
    }

    func rename(_ name: String) {
        meta.name = name
        persist()
    }

    func cancelPending() { pendingA = nil }

    private func mutate(_ id: UUID, _ change: (inout Measurement) -> Void) {
        guard let i = meta.measurements.firstIndex(where: { $0.id == id }) else { return }
        change(&meta.measurements[i])
    }

    private func persist() { try? store.update(meta) }
}
```

- [ ] **Step 3: Push, CI zielone**

Run: `git add -A && git commit -m "feat: measure view model" && git push && bash scripts/ci-wait.sh`
Expected: PASS.

---

### Task 7: Ekran pomiarów (MeasureView)

**Files:**
- Create: `Sources/Measure/MeasureView.swift`, `Sources/Measure/LoupeView.swift`, `Sources/Measure/ReliabilityColor.swift`

**Interfaces:**
- Consumes: `MeasureViewModel`, `ImageLayout`, `SensorGeometry`, `ImageOrientation.uiOrientation`, `Reliability`.
- Produces: `struct MeasureView: View { init(viewModel: MeasureViewModel, image: UIImage, onShare: @escaping () -> Void) }` (`image` = już obrócony do orientacji wyświetlania), `extension Reliability { var color: Color }`.

(Brak testów jednostkowych widoku — logika jest w Task 6; kontrola wizualna na telefonie w Task 10. Weryfikacja tu = kompilacja w CI.)

- [ ] **Step 1: Kolory i lupa**

`Sources/Measure/ReliabilityColor.swift`:
```swift
import SwiftUI

extension Reliability {
    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }
}
```
`Sources/Measure/LoupeView.swift`:
```swift
import SwiftUI

/// Okrągła lupa 3× z celownikiem; `center` = punkt w układzie wyświetlanego obrazu (0…1).
struct LoupeView: View {
    let image: UIImage
    let imageSize: CGSize        // rozmiar obrazu w widoku (layout.rect.size)
    let center: NormalizedPoint
    private let diameter: CGFloat = 120
    private let zoom: CGFloat = 3

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: imageSize.width * zoom, height: imageSize.height * zoom)
                .offset(x: diameter / 2 - CGFloat(center.x) * imageSize.width * zoom - imageSize.width * zoom / 2,
                        y: diameter / 2 - CGFloat(center.y) * imageSize.height * zoom - imageSize.height * zoom / 2)
            Circle().fill(.red).frame(width: 6, height: 6)
            Rectangle().fill(.red.opacity(0.7)).frame(width: 24, height: 1)
            Rectangle().fill(.red.opacity(0.7)).frame(width: 1, height: 24)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(radius: 4)
    }
}
```

- [ ] **Step 2: Główny widok**

`Sources/Measure/MeasureView.swift`:
```swift
import SwiftUI

struct MeasureView: View {
    @ObservedObject var viewModel: MeasureViewModel
    let image: UIImage            // obrócony do orientacji wyświetlania
    let onShare: () -> Void

    private enum Drag { case move(DragTarget), place }
    @State private var drag: Drag?
    @State private var touch: CGPoint?
    @State private var name = ""

    private var orientation: ImageOrientation { viewModel.meta.orientation }
    private let hitRadius: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let layout = ImageLayout(container: geo.size, displayed: image.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    Canvas { ctx, _ in draw(ctx, layout) }
                        .allowsHitTesting(false)
                    if let t = touch, layout.rect.width > 0 {
                        let d = layout.displayPoint(t)
                        LoupeView(image: image, imageSize: layout.rect.size, center: d)
                            .position(x: min(max(t.x, 70), geo.size.width - 70), y: max(t.y - 100, 70))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in onChanged(g.location, layout) }
                        .onEnded { g in onEnded(g.location, layout) }
                )
            }
            list
        }
        .navigationTitle(viewModel.meta.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { onShare() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(viewModel.meta.measurements.isEmpty)
            }
        }
        .onAppear { name = viewModel.meta.name }
    }

    // MARK: gesty

    private func project(_ layout: ImageLayout) -> (NormalizedPoint) -> CGPoint {
        { sensor in layout.viewPoint(SensorGeometry.toDisplay(sensor, orientation)) }
    }

    private func sensorPoint(_ v: CGPoint, _ layout: ImageLayout) -> NormalizedPoint {
        SensorGeometry.toSensor(layout.displayPoint(v), orientation)
    }

    private func onChanged(_ loc: CGPoint, _ layout: ImageLayout) {
        touch = loc
        if drag == nil {
            if let t = viewModel.hit(at: loc, radius: hitRadius, project: project(layout)) {
                drag = .move(t)
            } else {
                drag = .place
            }
        }
        if case .move(let t) = drag { viewModel.move(t, to: sensorPoint(loc, layout)) }
    }

    private func onEnded(_ loc: CGPoint, _ layout: ImageLayout) {
        switch drag {
        case .move: viewModel.commit()
        case .place: viewModel.place(at: sensorPoint(loc, layout))
        case nil: break
        }
        drag = nil
        touch = nil
    }

    // MARK: rysowanie

    private func draw(_ ctx: GraphicsContext, _ layout: ImageLayout) {
        let proj = project(layout)
        for m in viewModel.meta.measurements {
            let a = proj(m.a), b = proj(m.b)
            let r = viewModel.result(for: m)
            var line = Path(); line.move(to: a); line.addLine(to: b)
            ctx.stroke(line, with: .color(r.reliability.color), lineWidth: 2.5)
            for pt in [a, b] {
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)),
                         with: .color(r.reliability.color))
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)),
                           with: .color(.white), lineWidth: 1.5)
            }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let text = ctx.resolve(Text(r.label).font(.system(size: 14, weight: .bold)).foregroundColor(.black))
            let size = text.measure(in: CGSize(width: 200, height: 40))
            let box = CGRect(x: mid.x - size.width / 2 - 6, y: mid.y - size.height / 2 - 3,
                             width: size.width + 12, height: size.height + 6)
            ctx.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(.white.opacity(0.9)))
            ctx.draw(text, at: mid)
        }
        if let a = viewModel.pendingA {
            let pt = proj(a)
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)),
                       with: .color(.yellow), lineWidth: 3)
        }
    }

    // MARK: lista

    private var list: some View {
        List {
            Section {
                TextField("Nazwa zdjęcia", text: $name)
                    .onSubmit { viewModel.rename(name) }
            }
            Section("Pomiary") {
                if viewModel.meta.measurements.isEmpty {
                    Text(viewModel.pendingA == nil
                         ? "Przyłóż palec, przeciągnij lupą na punkt i puść — to punkt A. Potem tak samo punkt B."
                         : "Teraz wskaż punkt B.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(viewModel.meta.measurements) { m in
                    let r = viewModel.result(for: m)
                    HStack {
                        Circle().fill(r.reliability.color).frame(width: 10, height: 10)
                        Text(r.label).font(.headline.monospacedDigit())
                        Spacer()
                        Button(role: .destructive) { viewModel.delete(m.id) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }
}
```

- [ ] **Step 3: Push, CI zielone (kompilacja)**

Run: `git add -A && git commit -m "feat: measure screen" && git push && bash scripts/ci-wait.sh`
Expected: PASS. Błędy kompilacji SwiftUI (np. typy w `Canvas`) napraw w kolejnych commitach.

---

### Task 8: Renderer eksportu i arkusz udostępniania

**Files:**
- Create: `Sources/Export/OverlayRenderer.swift`, `Sources/Export/ShareSheet.swift`
- Test: `Tests/OverlayRendererTests.swift`

**Interfaces:**
- Consumes: `ShotMeta`, `DepthMap`, `MeasureEngine`, `SensorGeometry`, `Reliability.color` (UIColor wariant lokalnie).
- Produces:
  - `struct OverlayLine: Equatable { a: CGPoint; b: CGPoint; label: String; reliability: Reliability }` (punkty w pikselach wyświetlanego obrazu)
  - `enum OverlayRenderer { static func lines(for meta: ShotMeta, depth: DepthMap, displayedSize: CGSize) -> [OverlayLine]; static func render(image: UIImage, lines: [OverlayLine], title: String?) -> Data? }`
  - `struct ShareSheet: UIViewControllerRepresentable { init(items: [Any]) }`

- [ ] **Step 1: Testy**

`Tests/OverlayRendererTests.swift`:
```swift
import XCTest
import UIKit
@testable import PomiarMebli

final class OverlayRendererTests: XCTestCase {
    let k = CameraIntrinsics(fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)

    func whiteImage(_ w: Int, _ h: Int) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func pixel(_ img: UIImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img.cgImage!, at: CGPoint(x: -x, y: -(img.cgImage!.height - 1 - y)))
        return (px[0], px[1], px[2])
    }

    func testLinesUseEngineAndConvertToDisplayPixels() {
        let meta = ShotMeta(id: UUID(), name: "T", createdAt: Date(), intrinsics: k, depthWidth: 256, depthHeight: 192,
                            orientation: .up,
                            measurements: [Measurement(a: NormalizedPoint(x: 0.25, y: 0.5), b: NormalizedPoint(x: 0.75, y: 0.5))])
        let lines = OverlayRenderer.lines(for: meta, depth: .uniform(width: 256, height: 192, depth: 2.0),
                                          displayedSize: CGSize(width: 1920, height: 1440))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].label, "1280 mm")
        XCTAssertEqual(lines[0].a.x, 480, accuracy: 0.001)
        XCTAssertEqual(lines[0].b.y, 720, accuracy: 0.001)
    }

    func testLinesRespectOrientation() {
        let meta = ShotMeta(id: UUID(), name: "T", createdAt: Date(), intrinsics: k, depthWidth: 256, depthHeight: 192,
                            orientation: .right,
                            measurements: [Measurement(a: NormalizedPoint(x: 0, y: 0), b: NormalizedPoint(x: 1, y: 0))])
        let lines = OverlayRenderer.lines(for: meta, depth: .uniform(width: 256, height: 192, depth: 2.0),
                                          displayedSize: CGSize(width: 1440, height: 1920))
        XCTAssertEqual(lines[0].a, CGPoint(x: 1440, y: 0))      // sensor (0,0) -> prawy górny
        XCTAssertEqual(lines[0].b, CGPoint(x: 1440, y: 1920))   // sensor (1,0) -> prawy dolny
    }

    func testRenderKeepsSizeAndDrawsOnImage() throws {
        let img = whiteImage(400, 300)
        let line = OverlayLine(a: CGPoint(x: 50, y: 150), b: CGPoint(x: 350, y: 150), label: "1280 mm", reliability: .green)
        let data = try XCTUnwrap(OverlayRenderer.render(image: img, lines: [line], title: "Test"))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width * out.scale, 400)
        XCTAssertEqual(out.size.height * out.scale, 300)
        let p = pixel(out, 50, 150)                  // koniec odcinka — nie biały
        XCTAssertTrue(p.r < 250 || p.g < 250 || p.b < 250)
        let q = pixel(out, 380, 20)                  // narożnik bez rysunku — biały
        XCTAssertGreaterThan(q.r, 240)
    }

    func testRenderWithoutLinesStillProducesJPEG() {
        XCTAssertNotNil(OverlayRenderer.render(image: whiteImage(100, 100), lines: [], title: nil))
    }
}
```

- [ ] **Step 2: Implementacja**

`Sources/Export/OverlayRenderer.swift`:
```swift
import UIKit

struct OverlayLine: Equatable {
    var a: CGPoint
    var b: CGPoint
    var label: String
    var reliability: Reliability
}

enum OverlayRenderer {
    static func lines(for meta: ShotMeta, depth: DepthMap, displayedSize: CGSize) -> [OverlayLine] {
        meta.measurements.map { m in
            let r = MeasureEngine.measure(depth, meta.intrinsics, from: m.a, to: m.b)
            func px(_ s: NormalizedPoint) -> CGPoint {
                let d = SensorGeometry.toDisplay(s, meta.orientation)
                return CGPoint(x: d.x * displayedSize.width, y: d.y * displayedSize.height)
            }
            return OverlayLine(a: px(m.a), b: px(m.b), label: r.label, reliability: r.reliability)
        }
    }

    static func render(image: UIImage, lines: [OverlayLine], title: String?) -> Data? {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let unit = max(size.width, size.height) / 350      // grubość linii
        let font = UIFont.boldSystemFont(ofSize: max(size.width, size.height) / 40)

        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            let g = ctx.cgContext
            for l in lines {
                let color = uiColor(l.reliability)
                g.setStrokeColor(color.cgColor); g.setLineWidth(unit)
                g.move(to: l.a); g.addLine(to: l.b); g.strokePath()
                for p in [l.a, l.b] {
                    let r = unit * 2
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                    g.setFillColor(color.cgColor); g.fillEllipse(in: rect)
                    g.setStrokeColor(UIColor.white.cgColor); g.setLineWidth(unit / 2); g.strokeEllipse(in: rect)
                }
                drawPill(l.label, at: CGPoint(x: (l.a.x + l.b.x) / 2, y: (l.a.y + l.b.y) / 2), font: font, in: g)
            }
            if let title, !title.isEmpty {
                drawPill(title, at: CGPoint(x: size.width / 2, y: font.lineHeight * 1.2), font: font, in: g)
            }
        }
        return img.jpegData(compressionQuality: 0.9)
    }

    private static func uiColor(_ r: Reliability) -> UIColor {
        switch r {
        case .green: return UIColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)
        case .yellow: return UIColor.orange
        case .red: return UIColor.red
        }
    }

    private static func drawPill(_ text: String, at center: CGPoint, font: UIFont, in g: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let s = (text as NSString).size(withAttributes: attrs)
        let pad = font.pointSize * 0.4
        let box = CGRect(x: center.x - s.width / 2 - pad, y: center.y - s.height / 2 - pad / 2,
                         width: s.width + 2 * pad, height: s.height + pad)
        g.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        g.addPath(UIBezierPath(roundedRect: box, cornerRadius: pad).cgPath); g.fillPath()
        (text as NSString).draw(at: CGPoint(x: center.x - s.width / 2, y: center.y - s.height / 2), withAttributes: attrs)
    }
}
```
`Sources/Export/ShareSheet.swift`:
```swift
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 3: Push, CI zielone**

Run: `git add -A && git commit -m "feat: overlay renderer and share sheet" && git push && bash scripts/ci-wait.sh`
Expected: PASS. Jeśli `testRenderKeepsSizeAndDrawsOnImage` zawodzi na osi Y piksela, popraw helper `pixel` (pomiar jest w teście), nie rysowanie.

---

### Task 9: Galeria i spięcie aplikacji

**Files:**
- Create: `Sources/Gallery/GalleryView.swift`, `Sources/Gallery/ShotScreen.swift`
- Modify: `Sources/App/RootView.swift`, `Sources/App/PomiarMebliApp.swift`
- Test: `Tests/ShotImageTests.swift`

**Interfaces:**
- Consumes: wszystkie powyższe.
- Produces: `enum ShotImage { static func load(_ meta: ShotMeta, store: ShotStore) -> UIImage? }` (obraz z orientacją wyświetlania), `GalleryView`, `ShotScreen(store:id:)`, `RootView(store:)`.

- [ ] **Step 1: Test ładowania obrazu**

`Tests/ShotImageTests.swift`:
```swift
import XCTest
import UIKit
@testable import PomiarMebli

final class ShotImageTests: XCTestCase {
    func testLoadAppliesOrientationAndSwapsDisplayedSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShotStore(root: root)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: f).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }.jpegData(compressionQuality: 0.9)!
        let k = CameraIntrinsics(fx: 1, fy: 1, cx: 1, cy: 1, imageWidth: 200, imageHeight: 100)
        let meta = try store.save(CapturedShot(jpeg: jpeg, depth: .uniform(width: 2, height: 2, depth: 1),
                                               intrinsics: k, orientation: .right), name: "T", now: Date())
        let img = try XCTUnwrap(ShotImage.load(meta, store: store))
        XCTAssertEqual(img.size.width, 100)     // obrócony: szerokość = wysokość sensora
        XCTAssertEqual(img.size.height, 200)
    }

    func testLoadMissingFileReturnsNil() {
        let store = ShotStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString)"))
        let k = CameraIntrinsics(fx: 1, fy: 1, cx: 1, cy: 1, imageWidth: 1, imageHeight: 1)
        let meta = ShotMeta(id: UUID(), name: "", createdAt: Date(), intrinsics: k, depthWidth: 1, depthHeight: 1,
                            orientation: .up, measurements: [])
        XCTAssertNil(ShotImage.load(meta, store: store))
    }
}
```

- [ ] **Step 2: Implementacja ShotImage, ShotScreen, GalleryView**

`Sources/Gallery/ShotScreen.swift`:
```swift
import SwiftUI
import UIKit

enum ShotImage {
    static func load(_ meta: ShotMeta, store: ShotStore) -> UIImage? {
        guard let raw = UIImage(contentsOfFile: store.imageURL(for: meta.id).path),
              let cg = raw.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: meta.orientation.uiOrientation)
    }
}

/// Wczytuje zdjęcie + głębię i pokazuje MeasureView (albo komunikat o błędzie).
struct ShotScreen: View {
    let store: ShotStore
    let id: UUID

    @State private var state: LoadState = .loading
    @State private var shareURL: ShareItem?

    private enum LoadState { case loading, failed, ready(MeasureViewModel, UIImage) }
    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        Group {
            switch state {
            case .loading: ProgressView()
            case .failed: Text("Nie można wczytać zdjęcia (brak plików).").foregroundStyle(.secondary)
            case .ready(let vm, let image):
                MeasureView(viewModel: vm, image: image) { export(vm, image) }
            }
        }
        .task { load() }
        .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
    }

    private func load() {
        guard let meta = store.list().first(where: { $0.id == id }),
              let depth = store.loadDepth(meta),
              let image = ShotImage.load(meta, store: store) else { state = .failed; return }
        state = .ready(MeasureViewModel(meta: meta, depth: depth, store: store), image)
    }

    private func export(_ vm: MeasureViewModel, _ image: UIImage) {
        let lines = OverlayRenderer.lines(for: vm.meta, depth: vm.depth, displayedSize: image.size)
        guard let data = OverlayRenderer.render(image: image, lines: lines, title: vm.meta.name) else { return }
        let safe = vm.meta.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "pomiar" : safe).jpg")
        try? data.write(to: url, options: .atomic)
        shareURL = ShareItem(url: url)
    }
}
```
`Sources/Gallery/GalleryView.swift`:
```swift
import SwiftUI

struct GalleryView: View {
    let store: ShotStore
    let onNew: () -> Void
    let onOpen: (UUID) -> Void

    @State private var shots: [ShotMeta] = []
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            if shots.isEmpty {
                Text("Brak zdjęć. Dotknij +, aby zrobić pierwsze.")
                    .foregroundStyle(.secondary).padding(.top, 80)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shots) { meta in
                    Button { onOpen(meta.id) } label: { card(meta) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Usuń", role: .destructive) { store.delete(id: meta.id); reload() }
                        }
                }
            }.padding()
        }
        .navigationTitle("Pomiar mebli")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNew) { Image(systemName: "plus.circle.fill") }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { shots = store.list() }

    private func card(_ meta: ShotMeta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let img = ShotImage.load(meta, store: store)?.preparingThumbnail(of: CGSize(width: 400, height: 400)) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            Text(meta.name).font(.subheadline.bold()).lineLimit(1)
            Text("\(meta.measurements.count) pomiarów · \(meta.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: RootView i App**

`Sources/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    let store: ShotStore
    @State private var path: [UUID] = []
    @State private var showCapture = false

    init(store: ShotStore = ShotStore(root: ShotStore.defaultRoot())) {
        self.store = store
    }

    var body: some View {
        NavigationStack(path: $path) {
            GalleryView(store: store, onNew: { showCapture = true }, onOpen: { path.append($0) })
                .navigationDestination(for: UUID.self) { ShotScreen(store: store, id: $0) }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView(onCancel: { showCapture = false }, onCaptured: { shot in
                showCapture = false
                let f = DateFormatter()
                f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "yyyy-MM-dd HH:mm"
                if let meta = try? store.save(shot, name: "Pomiar \(f.string(from: Date()))") {
                    path.append(meta.id)
                }
            })
        }
    }
}
```
`Sources/App/PomiarMebliApp.swift` pozostaje bez zmian (`RootView()` używa domyślnego argumentu). `Tests/SmokeTests.swift`: `_ = RootView()` nadal się kompiluje.

- [ ] **Step 4: Push, CI zielone**

Run: `git add -A && git commit -m "feat: gallery and app wiring" && git push && bash scripts/ci-wait.sh`
Expected: PASS i artefakt `.ipa` w przebiegu.

---

### Task 10: Instrukcja, instalacja i test terenowy

**Files:**
- Create: `README.md`

- [ ] **Step 1: README**

`README.md` (po polsku) zawiera sekcje: **Co to jest** (1 akapit), **Jak zbudować** (push → Actions → artefakt `PomiarMebli-ipa`, albo `gh run download -n PomiarMebli-ipa`), **Instalacja na iPhone** (na Windowsie zainstaluj iTunes i iCloud ze strony apple.com — nie ze Sklepu Microsoft — oraz Sideloadly z sideloadly.io; podłącz telefon kablem, w Sideloadly wskaż `PomiarMebli.ipa`, podaj Apple ID, „Start”; na telefonie: Ustawienia → Ogólne → VPN i zarządzanie urządzeniem → zaufaj; w iOS 16+ włącz Tryb programisty; podpis ważny 7 dni → ponowna instalacja), **Użycie** (zdjęcie → wskaż punkty z lupą → kolory wiarygodności → udostępnij), **Znane ograniczenia** (LiDAR: szkło, połysk, czerń, krawędzie; zasięg 0,3–5 m).

- [ ] **Step 2: Lista kontrolna testu terenowego (w README)**

1. Zmierz miarą element ok. 1 m (np. szerokość drzwi) z odległości ~1,5 m, wprost na wprost — zapisz różnicę w mm.
2. Powtórz z odległości 3 m i pod kątem — zapisz różnice.
3. Zrób zdjęcie telefonem trzymanym pionowo, poziomo (w obie strony) i do góry nogami — sprawdź, że linie i obraz zgadzają się, a eksport wygląda tak samo jak ekran.
4. Wskaż punkt na szkle/lustrze/czarnym blacie — oczekiwane: czerwony lub „—”, bez crasha.
5. Wyeksportuj JPEG, udostępnij do Zdjęć i sprawdź czytelność etykiet.
6. Wyniki (rozbieżności w mm, kolory wiarygodności) wpisz do `docs/field-test-2026-XX-XX.md` — posłużą do strojenia progów (spec, sekcja 3).

- [ ] **Step 3: Commit i push**

```bash
git add README.md && git commit -m "docs: README and field test checklist

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" && git push && bash scripts/ci-wait.sh
```
Expected: PASS.

- [ ] **Step 4: Przekaż użytkownikowi `.ipa` i instrukcję instalacji**

Pobierz artefakt (`gh run download`), pokaż ścieżkę pliku, poprowadź instalację przez Sideloadly. Błędy z testu terenowego wracają jako zgłoszenia → poprawki → nowy przebieg CI.

---

## Self-Review

**Pokrycie specyfikacji:** zakres v1 (zdjęcie+głębia — Task 5; punkty na zamrożonym zdjęciu z lupą — Task 6/7; wiarygodność — Task 2/7; eksport JPEG — Task 8; galeria — Task 9), technika pomiaru (Task 2), architektura i pliki (Task 4), testy i CI bez Maca (Task 1, każdy task), publiczne repozytorium (Task 1), ryzyka (README, Task 10). Brak luk.

**Placeholdery:** brak „TBD/TODO”. README (Task 10) opisany treścią sekcji, nie kodem — to dokument, nie kod.

**Spójność typów:** `NormalizedPoint`, `CameraIntrinsics`, `DepthMap`, `Reliability`, `MeasurementResult.label` (Task 2) używane identycznie w Task 4–9; `ImageOrientation`/`SensorGeometry`/`ImageLayout` (Task 3) w Task 5, 7, 8, 9; `ShotStore.save(_:name:now:)` wywołane tak samo w testach i `RootView`; `OverlayRenderer.lines/render` (Task 8) użyte w `ShotScreen` (Task 9); `DragTarget` i `MeasureViewModel` API (Task 6) zgodne z `MeasureView` (Task 7).

**Review Focus:** każdy z 5 punktów ma test (Task 2: narożniki, brak pewności, identyczne punkty; Task 3: orientacje i mapowanie urządzenia; Task 5: brak LiDAR; Task 6: czerwony/„—” w VM).

**Znane ryzyka wykonawcze:** (1) mapowanie orientacji urządzenia → obrót obrazu (Task 3) jest zgodne z konwencją ARKit, ale potwierdzenie daje dopiero test terenowy w 4 orientacjach; (2) progi wiarygodności do strojenia po testach w terenie; (3) nazwa symulatora i etykieta runnera w CI mogą wymagać korekty (Task 1, krok 5).
