# Pomiar mebli — specyfikacja projektu

Data: 2026-10-16 · Status: do akceptacji użytkownika

## 1. Cel i zakres

Prosta aplikacja iOS do pomiarów przed wykonaniem mebli. Użytkownik robi zdjęcie
iPhone'em 14 Pro Max (LiDAR), a następnie na nieruchomym zdjęciu wskazuje punkty,
które chce zmierzyć. Odległości liczone są z danych głębi LiDAR. Wynikiem jest
zdjęcie z naniesionymi wymiarami (JPEG), które można udostępnić.

**Wersja 1 — w zakresie:**
- jedno zdjęcie + mapa głębi zapisane razem (tryb „najpierw zdjęcie, potem punkty"),
- dowolna liczba pomiarów punkt–punkt na zdjęciu, edytowalnych po fakcie,
- wskaźnik wiarygodności każdego pomiaru,
- eksport JPEG z wymiarami przez arkusz udostępniania iOS,
- lokalna galeria zapisanych zdjęć.

**Poza zakresem (świadomie, YAGNI):** skan pomieszczenia RoomPlan / rzut 2D,
pomiar na żywo w AR, GPS, mapa, upload na serwer, kategorie, wykrywanie dziur,
przyciąganie do krawędzi, dopasowanie płaszczyzn, iPad / inne iPhone'y bez LiDAR.

Źródła pomysłów: `escom-dev/holereport` (sesja AR z LiDAR, zapis zdjęć, rysowanie
nakładki) oraz `BaidetskyiYurii/RoomPlanDemo` (RoomPlan — odłożone na później).
Kod HoleReport jest tylko wzorcem; nowa aplikacja jest pisana od zera i oczyszczona
z funkcji drogowych.

## 2. Przebieg użytkownika

1. **Zdjęcie** — kamera z sesją AR (LiDAR). Przycisk migawki zapisuje klatkę.
2. **Pomiary** — zamrożone zdjęcie. Dotknięcie = punkt A, kolejne = punkt B, powstaje
   odcinek z wymiarem w mm. Końce przesuwa się palcem z lupą; pomiar można usunąć.
   Kolor wymiaru: zielony / żółty / czerwony = wiarygodność głębi.
3. **Eksport** — „Udostępnij" renderuje JPEG z liniami i wymiarami; użytkownik może
   nadać zdjęciu nazwę (np. „Kuchnia – wnęka lodówki").
4. **Galeria** — lista zapisanych zdjęć, otwarcie = powrót do edycji pomiarów.

## 3. Technika pomiaru

Przy zdjęciu zapisujemy z `ARFrame`: `capturedImage`, `sceneDepth.depthMap`
(Float32, metry, 256×192) i `confidenceMap` (UInt8), `camera.intrinsics`,
`camera.imageResolution` oraz orientację urządzenia.

Pomiar punktu 2D → 3D (w układzie kamery tej samej klatki; macierz położenia kamery
nie jest potrzebna, bo oba punkty należą do jednej klatki):

- współrzędne punktu przeliczane z obrazu na siatkę głębi (skala intrinsics),
- głębia = **mediana** z okna 5×5 pikseli, tylko piksele o wysokiej pewności;
  jeśli ważnych < 30% — okno 7×7 i wiarygodność „żółta"; brak ważnych → „czerwona",
  pomiar oznaczony jako niewiarygodny,
- `X = (u − cx)·Z/fx`, `Y = (v − cy)·Z/fy` (u, v, cx, cy, fx, fy w skali głębi),
- odległość = norma euklidesowa różnicy dwóch punktów 3D.

Wiarygodność (progi do strojenia po testach w terenie): zielona gdy ≥ 60% pikseli
okna ważnych i ≥ 80% ważnych pikseli mieści się w ±2% mediany (odporne na krawędzie
między planami); poza zakresem 0,3–5 m — żółta.
Znane słabości LiDAR: szkło, połyski, czarne powierzchnie, krawędzie (głębia
„rozmywa się" między planami) — stąd mediana, filtr pewności i kolor wiarygodności.

## 4. Architektura (SwiftUI, iOS 17+, Swift 5.9)

| Moduł | Odpowiedzialność | Zależności |
|---|---|---|
| `MeasureEngine` | czysta matematyka: skalowanie, odczyt głębi, 2D→3D, odległość, wiarygodność | tylko Foundation/simd |
| `Capture` | sesja ARKit (`sceneDepth`), migawka → `CapturedShot` | ARKit |
| `Store` | zapis/odczyt: `foto.jpg`, `depth.bin` (Float32 + UInt8), `meta.json` | Foundation |
| `MeasureView` | płótno, punkty, lupa, lista pomiarów | MeasureEngine |
| `Renderer` | rysowanie linii i etykiet na pełnym JPEG | UIKit |
| `Gallery` | lista zapisanych zdjęć | Store |

`meta.json`: nazwa, data, rozmiar obrazu, rozmiar głębi, intrinsics, orientacja,
lista pomiarów (punkty A/B w znormalizowanych współrzędnych obrazu).

Obraz z kamery jest w orientacji sensora (landscape); wyświetlanie obraca go do
orientacji zapisu, a współrzędne pomiarów są zawsze trzymane w układzie obrazu
sensora, żeby obrót nie psuł pomiarów.

## 5. Testowanie i budowanie bez Maca

- **Testy jednostkowe (XCTest) dla `MeasureEngine`**: syntetyczne mapy głębi
  (płaszczyzna na znanej odległości → znany wymiar; płaszczyzna pochylona; piksele
  niepewne i brakujące; krawędź między dwiema głębiami). Uruchamiane w CI.
- **CI: GitHub Actions (runner macOS)**: `xcodegen` generuje projekt z `project.yml`,
  `xcodebuild test` na symulatorze, następnie niepodpisany build na iOS i spakowanie
  do `.ipa` jako artefakt do pobrania.
- **Instalacja**: Sideloadly z Windowsa, podpis darmowym Apple ID (ważny 7 dni),
  ewentualnie później konto Apple Developer (TestFlight).
- **Weryfikacja LiDAR i dokładności**: wyłącznie na telefonie (nie da się tu
  zasymulować); pierwszy test terenowy na meblu o znanych wymiarach, rozbieżności
  służą do dostrojenia progów z sekcji 3.

Repozytorium: publiczne na koncie `rozkrojeszczecinek1-gif` (darmowe minuty macOS).

## 6. Ryzyka

- Brak Maca: kod ARKit/UI można sprawdzić dopiero na telefonie, więcej rund
  „zbuduj → przetestuj → opisz".
- Dokładność głębi LiDAR (256×192) bywa niewystarczająca dla małych elementów —
  ewentualna późniejsza poprawka: przyciąganie do krawędzi lub dopasowanie płaszczyzn.
- Wygasanie podpisu po 7 dniach przy darmowym Apple ID.
