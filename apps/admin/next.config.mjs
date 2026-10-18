const staticExport = process.env.RC_STATIC_EXPORT === '1';
if (staticExport) {
  const api = new URL(process.env.NEXT_PUBLIC_API_URL ?? '');
  if (
    api.protocol !== 'https:' ||
    api.username ||
    api.password ||
    api.search ||
    api.hash ||
    api.pathname !== '/v1'
  )
    throw Error('Static admin export requires NEXT_PUBLIC_API_URL=https://YOUR_API_HOST/v1');
}
export default staticExport ? { output: 'export', trailingSlash: true } : {};
