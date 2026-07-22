# Webinário Pompeu · Funil

Dashboard somente-leitura do funil de captação do **FDI** — dois webinários semanais
(**segunda** e **terça**). Site estático (GitHub Pages) alimentado por `build.ps1`, que lê
as planilhas Google via *gviz CSV* e escreve `data.js` (agregado/anonimizado).

## Abas
- **Segunda / Terça** — um funil por aba. Investimento (Google, Meta, total), CPL,
  alcance/cliques, taxa de resposta da pesquisa, qualificados (leadscore) e **duas colunas
  de otimização** lado a lado (Google e Meta) com árvore campanha › conjunto › anúncio,
  CPL, CPL qualificado e tag de ação (Acelerar / Manter / Revisar / Atenção / Dado insuf.).
- **Pesquisa** — respostas da pesquisa de qualificação por webinário (segunda, terça e soma),
  distribuição de leadscore, perfil do lead qualificado e o que os leads respondem em cada
  uma das 8 dimensões.

## Regras
- **Imposto ×1,1385 apenas no Meta Ads** (Google Ads sem imposto).
- **Leadscore (protocolo v1.1)**: 8 dimensões, score 0–15 → Frio 0–4 · Morno 5–10 ·
  **Quente 11–15 = Qualificado**. As métricas de qualificação são acumuladas desde 10/07/2026.
- Atribuição lead → campanha/conjunto/anúncio via UTM. Pesquisa cruzada ao lead por e-mail/telefone.

## Atualização
100% na nuvem. `build.ps1` roda no GitHub Actions (`refresh.yml`) e publica no Pages.
Gatilho confiável: **cron-job.org** faz POST no `workflow_dispatch` a cada 3h.

## Fontes (somente leitura)
- Leads + pesquisa: planilha `1uRdsI3QhyvbRT7Q0sZa8y9DiFWOt8yaY68F134zrO20`
- Queries (Meta/Google): planilha `1RlFtbOJq4LUS8nc3MrR6C9-dvYA5-mSVpVQsHcPGNEE`
