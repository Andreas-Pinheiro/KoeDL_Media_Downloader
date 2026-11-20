# Patrocinador discreto / Discreet sponsor

O KoeDL mostra **no máximo uma faixa de 1 linha** acima do rodapé, escrita "Patrocinado", com botão de fechar. Sem pop-up, sem som, sem vídeo, sem rastreamento e sem script de terceiros. Quem não quiser desliga em *Configurações*.
The app shows **at most one 1-line strip** above the footer, labelled "Sponsored", with a close button. No pop-ups, sound, video, tracking or third-party scripts. It can be turned off in *Settings*.

Os anúncios vêm do arquivo [`ads.json`](ads.json) (branch `main`); lista vazia = nada aparece, e sem internet também não aparece nada.

```json
{ "ads": [ { "id": "meu-patrocinador", "text": { "pt": "Texto curto", "en": "Short text" },
             "url": "https://exemplo.com", "from": "2026-12-01", "to": "2026-12-31", "weight": 1 } ] }
```
Só links `https://`; `from`/`to`/`weight` são opcionais (`weight` sorteia entre vários).
