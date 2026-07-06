#!/bin/bash
# =============================================================================
# Script para regenerar la documentación web del data lake
# Ejecutar después de cada cambio en los archivos .tf
# Uso: ./docs/generate.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "📄 Generando documentación..."
echo "   Proyecto: $PROJECT_DIR"

# Actualizar timestamp en el HTML
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|Última actualización:.*</p>|Última actualización: $(date '+%Y-%m-%d %H:%M:%S')</p>|" "$SCRIPT_DIR/index.html"
else
    sed -i "s|Última actualización:.*</p>|Última actualización: $(date '+%Y-%m-%d %H:%M:%S')</p>|" "$SCRIPT_DIR/index.html"
fi

# Generar grafo de Terraform (requiere graphviz instalado)
cd "$PROJECT_DIR"
if command -v terraform &> /dev/null && command -v dot &> /dev/null; then
    echo "   Generando grafo de dependencas Terraform..."
    terraform graph 2>/dev/null | dot -Tsvg > "$SCRIPT_DIR/terraform_graph.svg" 2>/dev/null
    echo "   ✅ Grafo guardado en docs/terraform_graph.svg"
else
    echo "   ⚠️  Instala terraform + graphviz para generar el grafo SVG"
fi

echo ""
echo "✅ Documentación lista en: $SCRIPT_DIR/index.html"
echo "   Abre con: open $SCRIPT_DIR/index.html"
