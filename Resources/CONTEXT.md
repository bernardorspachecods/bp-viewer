# Contexto de `Resources/`

Recursos estáticos do bundle macOS: `BPViewer-Info.plist` define metadata da
app, enquanto `BPViewer.icns` e `BPViewer-logo.svg` são os recursos visuais.

`scripts/build-app.sh` copia o plist e o ícone para o bundle local. Não colocar
segredos, dados de projeto ou artefactos de compilação neste diretório.
