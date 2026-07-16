// Filtro de texto para listas JÁ carregadas na página (rankings, situação…).
// Insensível a acento e caixa — resolve "achar o item na lista" sem ida ao servidor.
// (Não é busca vetorial/semântica: para nomes próprios de ≤100 linhas, substring
//  normalizada é o que dá o melhor custo-benefício.)
export function normalizeText(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
}

// true quando `query` está vazia (não filtra) ou é substring normalizada de `text`.
export function matchesQuery(text: string, query: string): boolean {
  const q = normalizeText(query.trim())
  return q === '' || normalizeText(text).includes(q)
}
