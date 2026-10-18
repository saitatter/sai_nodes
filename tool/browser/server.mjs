import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../', import.meta.url));
export async function serveGallery() {
  const build = resolve(root, 'example/build/web');
  if (!existsSync(resolve(build, 'index.html'))) throw new Error('Build the gallery web target first.');
  const server = createServer((request, response) => {
    const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if (!path.startsWith('/sai_nodes/')) { response.writeHead(404).end(); return; }
    const file = resolve(build, path.slice('/sai_nodes/'.length) || 'index.html');
    if (!file.startsWith(build + sep) || !existsSync(file) || !statSync(file).isFile()) { response.writeHead(404).end(); return; }
    response.setHeader('Content-Type', {'.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf'}[extname(file)] ?? 'application/octet-stream');
    response.end(readFileSync(file));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {server, url: `http://127.0.0.1:${server.address().port}/sai_nodes/`};
}
