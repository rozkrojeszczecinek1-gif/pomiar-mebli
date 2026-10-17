# HANDOFF — Pomiar mebli (stan na 2026-10-17)

Plik do kontynuowania pracy na innym komputerze (także z Claude Code).

## Gdzie co jest

- Repozytorium (publiczne): https://github.com/rozkrojeszczecinek1-gif/pomiar-mebli
- Gałąź robocza: **`v1`** (nic nie jest jeszcze scalone do `main`; `main` ma tylko spec i plan)
- Specyfikacja: `docs/superpowers/specs/2026-10-16-pomiar-mebli-design.md`
- Plan implementacji (10 zadań, pełny kod): `docs/superpowers/plans/2026-10-16-pomiar-mebli.md`
- Lokalna kopia na pierwszym komputerze: `E:\pomiar-mebli`

## Jak wznowić na innym komputerze

```bash
git clone https://github.com/rozkrojeszczecinek1-gif/pomiar-mebli
cd pomiar-mebli
git checkout v1
```

Narzędzia: `git`, `gh` (GitHub CLI; `winget install GitHub.cli`) i zalogowanie `gh auth login`
(konto `rozkrojeszczecinek1-gif`, potrzebne uprawnienia `repo` i **`workflow`** — bez `workflow`
GitHub odrzuci push zmian w `.github/workflows/`). Po `gh auth setup-git` zwykły `git push` działa.

Nie ma Maca ani Xcode: **kompilacja i testy działają tylko w GitHub Actions** (runner macOS).
Skrypt `scripts/ci-wait.sh` po pushu czeka na wynik CI dla bieżącego commita, a przy błędzie
drukuje logi (przebieg trwa ok. 5 minut; flaga `-quiet` ukrywa treść asercji, więc przy
czerwonym teście trzeba wnioskować z nazwy testu lub chwilowo zdjąć `-quiet` w `ci.yml`).

Prompt na start dla Claude Code: *„Przeczytaj HANDOFF.md, plan i spec w tym repo i dokończ
zadanie 10 oraz końcowy przegląd, zgodnie z executing-plans.”*

## Stan wykonania planu

| Zadanie | Stan |
|---|---|
| 1 Szkielet, repo, CI | gotowe, CI zielone |
| 2 `MeasureEngine` | gotowe, testy zielone |
| 3 Geometria / orientacja | gotowe, testy zielone |
| 4 Modele i `ShotStore` | gotowe, testy zielone |
| 5 Przechwytywanie ARKit | gotowe, testy zielone (kompiluje się; **nieprzetestowane na telefonie**) |
| 6 `MeasureViewModel` | gotowe, testy zielone |
| 7 `MeasureView` + lupa | gotowe, kompiluje się; **nieprzetestowane na telefonie** |
| 8 Renderer eksportu | gotowe, testy zielone |
| 9 Galeria i spięcie aplikacji | gotowe, testy zielone |
| 10 README + test terenowy | gotowe (README napisany) |
| Końcowy przegląd całej gałęzi | gotowe (9 bugów naprawionych, commit d227bf5) |

Ostatni zielony przebieg CI: run `39021602239` (commit `d227bf5`). Artefakt **`PomiarMebli-ipa`**
(niepodpisany `.ipa`) można pobrać: `gh run download 38911196591 -n PomiarMebli-ipa`
(artefakty wygasają po ok. 90 dniach).

Plik IPA pobrany lokalnie: `D:\pomiar-mebli\PomiarMebli.ipa`

## Co zostało

1. **Test na iPhonie 14 Pro Max**: instalacja `.ipa` przez Sideloadly (darmowe Apple ID artur428@wp.pl, podpis
   ważny 7 dni), potem lista z Taska 10. Najważniejsze do sprawdzenia:
   - orientacja: zdjęcie pionowo, poziomo (obie strony) i do góry nogami — punkty muszą wypadać
     w tych samych miejscach obrazu, a eksport wyglądać jak ekran,
   - dokładność: element ok. 1 m z 1,5 m i z 3 m — różnica względem miary w mm,
   - lupa: czy celownik pokrywa się z miejscem dotknięcia,
   - szkło / lustro / czarny blat → czerwony lub „—”, bez crasha.

## Decyzje podjęte po drodze (rulings)

- Praca na gałęzi `v1` zamiast osobnego worktree (repozytorium nowe, bez innych gałęzi).
- Spec sekcja 3 zmieniona: kryterium zielonej wiarygodności to „≥ 60% pikseli okna ważnych
  i ≥ 80% ważnych w ±2% mediany” (zamiast MAD < 1,5%) — MAD nie wykrywał krawędzi 60/40.
- Plan zawierał błędne oczekiwanie w `testLayoutFitsAndCenters` (offset Y to 133,33, nie 100) —
  poprawiono test.
- `testUpdatePersistsMeasurements` używa daty z pełnych sekund: ISO8601 w `meta.json` gubi
  ułamki sekund (skutek: dwa zdjęcia z tej samej sekundy mogą mieć niejednoznaczną kolejność).
- `LoupeView`: uproszczony offset `-(center-0.5)*size*zoom` (wzór z planu liczył połowę średnicy
  podwójnie). **Do potwierdzenia wizualnie na telefonie.**
- `CaptureController.isSupported` jest `nonisolated` (test wywoływał ją poza głównym wątkiem).
- Pomocnik `pixel()` w `OverlayRendererTests` używa `CGContext.draw(_:in:)` (w planie było
  nieistniejące `draw(at:)`).

## Znane ryzyka

- Mapowanie orientacji urządzenia → obrót obrazu (`SensorGeometry.imageOrientation`) zgodne
  z konwencją ARKit, ale potwierdzenie dopiero na urządzeniu.
- Progi wiarygodności (okno 5×5/7×7, 60%, 80%, ±2%, zakres 0,3–5 m) to wartości startowe do
  strojenia po teście terenowym.
- Podpis darmowym Apple ID wygasa po 7 dniach (ponowna instalacja przez Sideloadly).
