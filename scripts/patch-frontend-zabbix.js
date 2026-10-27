#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const webRoot = path.resolve(process.argv[2] || process.env.ZBXTABLE_WEB_DIR || '');
if (!webRoot || !fs.existsSync(path.join(webRoot, 'package.json'))) {
  throw new Error('Usage: node scripts/patch-frontend-zabbix.js <zbxtable-web-source-directory>');
}

function edit(relativePath, transform) {
  const filename = path.join(webRoot, relativePath);
  const original = fs.readFileSync(filename, 'utf8');
  const updated = transform(original);
  if (updated !== original) fs.writeFileSync(filename, updated, 'utf8');
}

edit('app/api/pro2.js', source => {
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
  return source.replace("redirect:'/system/license'", "redirect:'/system/zabbix'");
});

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

