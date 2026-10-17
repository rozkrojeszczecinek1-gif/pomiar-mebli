# Pomiar mebli

Aplikacja iOS na iPhone z LiDAR (12 Pro lub nowszy). Robisz zdjęcie, wskazujesz dwa punkty za pomocą lupy i odczytujesz wymiar w milimetrach. Wynik eksportujesz jako JPEG z naniesionymi liniami i etykietami.

---

## Jak zbudować

Kompilacja działa wyłącznie w GitHub Actions (runner macOS) — bez Maca lokalnie nic się nie zbuduje.

1. Wypchnij zmiany na gałąź `v1`:
   ```bash
   git push
   ```
2. Otwórz zakładkę **Actions** w repozytorium — przebieg startuje automatycznie.
3. Po ok. 5 minutach pobierz artefakt `PomiarMebli-ipa`:
   ```bash
   gh run download --name PomiarMebli-ipa
   ```
   lub wejdź na stronę przebiegu i pobierz ręcznie z sekcji *Artifacts*.

---

## Instalacja na iPhone (Windows, bez konta dewelopera)

### Wymagania
- iPhone 12 Pro lub nowszy (LiDAR), iOS 17.0+
- iTunes i iCloud **ze strony apple.com** (nie ze Sklepu Microsoft):
  - <https://www.apple.com/pl/itunes/>
  - <https://support.apple.com/pl-pl/HT204283>
- [Sideloadly](https://sideloadly.io/) — darmowe narzędzie do instalacji `.ipa`
- Kabel USB-C / Lightning do telefonu

### Kroki
1. Zainstaluj iTunes i iCloud (jeśli jeszcze nie masz).
2. Zainstaluj Sideloadly.
3. Podłącz iPhone kablem do komputera i odblokuj go.
4. Uruchom Sideloadly, przeciągnij plik `PomiarMebli.ipa` na okno aplikacji.
5. Wpisz swoje Apple ID (darmowe wystarczy) i kliknij **Start**.
6. Na telefonie: **Ustawienia → Ogólne → VPN i zarządzanie urządzeniem** → znajdź swoje Apple ID → **Zaufaj**.
7. W iOS 16+: **Ustawienia → Prywatność i bezpieczeństwo → Tryb programisty** → włącz (wymaga restartu).

> **Uwaga:** Podpis darmowym Apple ID jest ważny **7 dni**. Po upływie tego czasu zainstaluj aplikację ponownie przez Sideloadly (bez usuwania danych).

---

## Użycie

1. Na ekranie galerii dotknij **+**, aby zrobić nowe zdjęcie.
2. Skieruj aparat na mierzony obiekt i naciśnij spust — obraz zostaje zamrożony.
3. Przyłóż palec do punktu A, przeciągnij lupą dokładnie na krawędź i puść.
4. Powtórz dla punktu B — pojawi się linia z wymiarem w mm.
5. Kolor linii oznacza wiarygodność pomiaru:
   - **Zielony** — wysoka pewność głębi, obiekt w zasięgu 0,3–5 m
   - **Żółty** — umiarkowana pewność (krawędź, dystans poza optymalnym zakresem)
   - **Czerwony** — brak wiarygodnych danych głębi; wynik „—"
6. Dotknij ikony udostępniania, aby wyeksportować JPEG z naniesionymi liniami.

---

## Znane ograniczenia

- **LiDAR nie radzi sobie z:** szkłem, lustrami, błyszczącymi powierzchniami, czarnym blatem — punkty na takich miejscach dają czerwony kolor lub „—".
- **Zasięg roboczy:** 0,3–5 m. Poniżej 30 cm i powyżej 5 m wynik jest żółty (dane mniej pewne).
- **Krawędzie między planami** (np. krawędź blatu przed ścianą) mogą dać żółty wynik dla punktów blisko krawędzi.
- **Podpis darmowym Apple ID** wygasa po 7 dniach — konieczna ponowna instalacja przez Sideloadly.
- Aplikacja działa tylko w **trybie pionowym** (portret).

---

## Lista kontrolna testu terenowego

Wykonaj poniższe punkty po pierwszej instalacji i zapisz wyniki w `docs/field-test-YYYY-MM-DD.md` — posłużą do ewentualnego dostrojenia progów wiarygodności (spec, sekcja 3).

1. **Dokładność z bliskiej odległości:** zmierz miarą element ok. 1 m (np. szerokość drzwi) z odległości ~1,5 m, wprost. Porównaj z wynikiem aplikacji i zapisz różnicę w mm.
2. **Dokładność z dalszej odległości i pod kątem:** powtórz pomiar z ~3 m i pod kątem ~30°. Zapisz różnicę.
3. **Orientacja urządzenia:** zrób zdjęcia trzymając telefon **pionowo**, **poziomo w obie strony** i **do góry nogami**. Sprawdź, że:
   - linie i punkty trafiają w te same miejsca obrazu niezależnie od orientacji,
   - wyeksportowany JPEG wygląda tak samo jak ekran.
4. **Trudne powierzchnie:** wskaż punkt na **szkle / lustrze / czarnym blacie** — oczekiwane: kolor czerwony lub etykieta „—", bez zamrożenia ani crashu.
5. **Eksport:** wyeksportuj JPEG, udostępnij do Zdjęć i sprawdź czytelność etykiet oraz poprawność linii na wydruku/ekranie.
6. Wpisz wszystkie rozbieżności i obserwacje do `docs/field-test-YYYY-MM-DD.md`.
