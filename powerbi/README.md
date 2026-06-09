# Power BI Report (PBIP)

Power BI Project v "Developer mode" formátu (source-control friendly, místo binárního `.pbix` jsou všechno textové JSON / TMDL soubory). Reportuje nad `l1.v_analysis` a `l1.v_analysis_live`.

## Otevření v Power BI Desktop

**Předpoklad:** Power BI Desktop (Windows). Mac users → použij Power BI Service web nebo VM s Windows.

1. **Enable Developer mode** v Power BI Desktop (jednorázově):
   `File → Options and settings → Options → Preview features → "Power BI Project (.pbip) save option"` ✅, restart.
2. **Otevři projekt:** `File → Open → powerbi/VSE_01_pbip.pbip`
3. Power BI se zeptá na **přihlášení k Azure SQL** — použij svůj `@vse.cz` účet (Microsoft account / Entra ID).
4. **Refresh:** Home → Refresh (stáhne data podle definice modelu).

## Struktura

```
powerbi/
├── VSE_01_pbip.pbip                    # root file (otevři tento)
├── VSE_01_pbip.Report/                 # Report (visualy, pages, bookmarky)
│   ├── definition/
│   │   ├── pages/                      # 6 dashboard pages
│   │   ├── bookmarks/                  # 12 uložených pohledů
│   │   ├── pages.json, report.json
│   │   └── version.json
│   └── StaticResources/                # theme + logo
└── VSE_01_pbip.SemanticModel/          # data model
    └── definition/
        ├── model.tmdl                  # model metadata
        ├── relationships.tmdl          # vztahy mezi tabulkami
        ├── database.tmdl
        ├── cultures/en-US.tmdl
        └── tables/
            ├── Calendar.tmdl                  # custom kalendář + DAX
            ├── 'l1 v_analysis.tmdl'           # main analytical view
            ├── 'l1 v_analysis_live.tmdl'     # live (poslední 3 měsíce)
            └── LocalDateTable_*.tmdl          # auto-generated time tables
```

## Co je v reportu

6 dashboard pages: různé pohledy na analytiku (per-test, per-product, live, watchdog stav, …).

Klíčové DAX measures (definované v `l1 v_analysis.tmdl`):
- `LSL` / `USL` — Lower/Upper Specification Limits (median z `limit_min`/`limit_max`)
- `Count of Tests` — DISTINCTCOUNT testů
- `First Pass Count` — kusy které prošly napoprvé (`loop_counter = 1`)
- `Retested Count` — kusy které musely být přetestovány

## Co NENÍ v gitu (gitignored, lokální only)

- `.pbi/cache.abf` — binární cache (~80 MB, generuje se lokálně po otevření)
- `.pbi/localSettings.json` — uživatelská nastavení (obsahuje šifrované tokeny)
- `.pbi/editorSettings.json` — editor preference

Tyto soubory si Power BI vygeneruje sám při prvním otevření projektu.

## Workflow při úpravách

```bash
git checkout -b feature/pbi-<co-delas>
# otevři projekt v PBI Desktop, edituj
# File → Save (uloží zpět do .tmdl / .json — source-control friendly)
git add powerbi/
git status                           # zkontroluj, že .pbi/* a *.abf NEJSOU staged
git commit -m "feat: pbi - ..."
git push -u origin feature/pbi-<co-delas>
# → vytvoř PR na GitHubu
```

## Souvislosti

Report čte z databáze přes `l1.v_analysis` a `l1.v_analysis_live`. Definice těchto views je v repu:
- [../sql/05_views/01_v_analysis.sql](../sql/05_views/01_v_analysis.sql)
- [../sql/05_views/03_v_analysis_live.sql](../sql/05_views/03_v_analysis_live.sql)

Pokud upravíš views v SQL (např. přidáš sloupec), musíš v Power BI Desktop udělat **Home → Refresh → "Refresh visuals"** a případně přidat sloupec do tabulky.
