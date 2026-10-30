#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const webRoot = path.resolve(process.argv[2] || process.env.ZBXTABLE_WEB_DIR || '');
if (!webRoot || !fs.existsSync(path.join(webRoot, 'package.json'))) {
  throw new Error('Usage: node scripts/patch-frontend-zabbix.js <zbxtable-web-source-directory>');
}

// The official frontend moved from the legacy app/... layout to the current
// src/... Vue layout. The current tree already contains the Zabbix integration
// page and service, so applying the legacy string patches would only make the
// CI build fail with misleading "file is missing" errors. Keep the official
// pages intact and validate the files that must be present in the new layout.
if (fs.existsSync(path.join(webRoot, 'src/router/index.js'))) {
  const requiredModern = [
    'src/router/index.js',
    'src/pages/dashboard/index.vue',
    'src/pages/host/AssetBrowser.vue',
    'src/pages/alarm/query.vue',
    'src/pages/report/host.vue',
    'src/pages/system/zabbix.vue',
    'src/services/zabbix.js',
  ];
  const missingModern = requiredModern.filter(file => !fs.existsSync(path.join(webRoot, file)));
  if (missingModern.length) {
    throw new Error(`Official Vue frontend is incomplete; missing: ${missingModern.join(', ')}`);
  }
  console.log(`Official Vue frontend detected at ${webRoot}; legacy patch is not required.`);
  process.exit(0);
}

function edit(relativePath, transform) {
  const filename = path.join(webRoot, relativePath);
  const original = fs.readFileSync(filename, 'utf8');
  const updated = transform(original);
  if (updated !== original) fs.writeFileSync(filename, updated, 'utf8');
}

// Fail the build if its frontend baseline has lost a page that ships with the
// official v3.0.x UI. Extensions must be additive; a successful build alone
// does not prove that the upstream product navigation is still present.
function requireSource(relativePath, fragments) {
  const filename = path.join(webRoot, relativePath);
  if (!fs.existsSync(filename)) throw new Error(`Required official frontend file is missing: ${relativePath}`);
  const source = fs.readFileSync(filename, 'utf8');
  for (const fragment of fragments) {
    if (!source.includes(fragment)) {
      throw new Error(`Official frontend baseline check failed: ${relativePath} is missing ${fragment}`);
    }
  }
}

requireSource('app/router/index.js', [
  "path:'/dashboard'", "path:'/srcManage'", "path:'/host'", "path:'/groups'",
  "path:'/templates'", "path:'/graph'", "path:'/report'", "path:'/export'",
  "path:'/inspect'", "path:'/alarm'", "path:'/analysis'", "path:'/query'",
  "path:'/system'", "path:'/chpwd'", "path:'/login'",
]);
for (const relativePath of [
  'app/views/dashboard/index.jsx',
  'app/views/srcManage/index.jsx',
  'app/views/srcManage/groups.jsx',
  'app/views/srcManage/templates.jsx',
  'app/views/srcManage/graph.jsx',
  'app/views/report/index.jsx',
  'app/views/alarm/index.jsx',
  'app/views/alarm/query.jsx',
  'app/views/system/chpwd.jsx',
  'app/views/user/index.jsx',
]) {
  requireSource(relativePath, ['import', 'export']);
}

edit('app/api/pro2.js', source => {
  // The customized build intentionally omits the optional authorization
  // information page from the official menu and API map.
  source = source.replace(/\s*license:\{url:'\/license'\},?/g, '');
  if (source.includes('zabbix:{')) return source;
  const marker = '\n};\n\nexport default apis;';
  if (!source.includes(marker)) throw new Error('Cannot find the API map insertion point in app/api/pro2.js');
  const block = `
  zabbix:{
    instances:{url:'/zabbix/instance'},
    instance:id=>({url:'/zabbix/instance/'+id}),
    testConfig:{url:'/zabbix/instance/test',method:'post'},
    test:id=>({url:'/zabbix/instance/'+id+'/test',method:'post'}),
    create:{url:'/zabbix/instance',method:'post'},
    update:id=>({url:'/zabbix/instance/'+id,method:'put'}),
    remove:id=>({url:'/zabbix/instance/'+id,method:'delete'}),
    enabled:id=>({url:'/zabbix/instance/'+id+'/enabled',method:'put'}),
  },`;
  return source.replace(marker, `\n${block}${marker}`);
});

edit('app/api/api.js', source => {
  source = source.replace('system:{license,chpwd},', 'system:{chpwd},');
  source = source.replace(/\nexport const getLicense=.*?;\n/g, '\n');
  if (source.includes('getZabbixInstances=')) return source;
  const marker = /export const chpwdFn=.*?;\s*/;
  if (!marker.test(source)) throw new Error('Cannot find the API export insertion point in app/api/api.js');
  const exports = `
export const getZabbixInstances=()=>fetcher({...apis.zabbix.instances});
export const getZabbixInstance=id=>fetcher({...apis.zabbix.instance(id)});
export const testZabbixConfig=data=>fetcher({...apis.zabbix.testConfig,data});
export const testZabbixInstance=id=>fetcher({...apis.zabbix.test(id)});
export const createZabbixInstance=data=>fetcher({...apis.zabbix.create,data});
export const updateZabbixInstance=(id,data)=>fetcher({...apis.zabbix.update(id),data});
export const deleteZabbixInstance=id=>fetcher({...apis.zabbix.remove(id)});
export const setZabbixInstanceEnabled=(id,data)=>fetcher({...apis.zabbix.enabled(id),data});
`;
  return source.replace(marker, match => `${match.trimEnd()}\n${exports}`);
});

edit('app/router/index.js', source => {
  if (!source.includes("path:'/zabbix'")) {
    const marker = "        icon:<SettingOutlined />,\n        children:[";
    if (!source.includes(marker)) throw new Error('Cannot find the System menu insertion point in app/router/index.js');
    const route = `        icon:<SettingOutlined />,
        children:[
          {
            path:'/zabbix',
            name:nameList['/zabbix'],
            icon:<CloudServerOutlined />,
            component:()=>import('../views/system/zabbix'),
          },`;
    source = source.replace(marker, route);
  }
  source = source.replace("redirect:'/system/license'", "redirect:'/system/zabbix'");
  source = source.replace(/\s*\{\s*path:'\/license',[\s\S]*?component:\(\)=>import\('\.\.\/views\/system'\),\s*\},\s*/, '\n');
  return source;
});

for (const language of ['zh', 'en']) {
  edit(`app/i18n/${language}/router.js`, source => {
    return source.replace(/^\s*['"]\/license['"]\s*:\s*[^,]+,\s*\r?\n?/m, '');
  });
}

edit('scripts/webpack.config.js', source => source.replace(
  "chunkFilename:'js/[name]_[chunkhash:8].chunk.js'",
  "chunkFilename:'js/[chunkhash:8].chunk.js'",
));

edit('scripts/webpack.production.js', source => source
  .replace("filename:'css/[name]_[contenthash:8].css'", "filename:'css/[contenthash:8].css'")
  .replace("chunkFilename:'css/[id]_[name]_[contenthash:8].css'", "chunkFilename:'css/[contenthash:8].css'")
  .replace("chunkFilename:'css/[id]_[contenthash:8].css'", "chunkFilename:'css/[contenthash:8].css'"));

for (const [language, label] of [['zh', 'Zabbix 对接'], ['en', 'Zabbix Integrations']]) {
  edit(`app/i18n/${language}/router.js`, source => {
    if (source.includes("'/zabbix'")) return source;
    const marker = /^\s*['"]\/chpwd['"]\s*:\s*[^,]+,/m;
    if (!marker.test(source)) throw new Error(`Cannot find the change-password translation in app/i18n/${language}/router.js`);
    return source.replace(marker, match => `${match}\n  '/zabbix': '${label}',`);
  });
}

const pageSource = path.join(__dirname, '..', 'frontend-patches', 'views', 'system', 'zabbix.jsx');
const pageDestination = path.join(webRoot, 'app', 'views', 'system', 'zabbix.jsx');
fs.mkdirSync(path.dirname(pageDestination), {recursive: true});
fs.copyFileSync(pageSource, pageDestination);
console.log(`Zabbix integration page patched into ${webRoot}`);

