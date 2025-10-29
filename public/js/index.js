function getIndexBody() {
  mappings = request("get", "./index/mappings")
  if (mappings.code != 0) {
    alert(mappings.msg);
    return;
  }
  mappings = mappings.data
  tabs = mappings.map(x => {
    return {
      title: x.name,
      tab: getTabBody(x)
    };
  });

  return {
    type: "page",
    body: [
      {
        type: "tabs",
        tabsMode: "vertical",
        tabs: tabs
      }
    ]
  };
}

function getTabBody(m) {
  if (m.log_type == "json") {
    return getParsedTab(m);
  } else if (m.log_regex) {
    return getParsedTab(m);
  } else {
    return getRawTab(m);
  }
}

function getRawTab(m) {
  return {
    type: "page",
    body: [
      {
        type: "service",
        api: "./search/logs?name=" + m.name + "&log_type=" + m.log_type + "&query=${query}",
        syncLocation: false,
        initFetch: false,
        body: [
          {
            type: "search-box",
            name: "query",
            align: "right",
            placeholder: "query"
          },
          {
            type: "pagination-wrapper",
            perPage: 10,
            body: [
              {
                type: "list",
                listItem: {
                  body: [
                    {
                      type: "tpl",
                      tpl: "${log}"
                    },
                    {
                      type: "each",
                      source: "${tags}",
                      items: {
                          type: "tpl",
                          tpl: "<span class='label label-info m-l-sm'><%= data.label %>: <%= data.value %></span>"
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]
      }
    ]
  };
}

function getParsedTab(m) {
  let tabName = `${m.name}_tab`;
  let eventName = m.name + "_query_changed";
  let tabEventCallback = {};
  tabEventCallback[eventName] = {
    actions: [
      {
        actionType: "reload",
        componentId: tabName
      }
    ]
  };
  return {
    id: tabName,
    type: "crud",
    api: {
      method: "get",
      url: "./search/logs?name=" + m.name + "&log_type=" + m.log_type + "&query=${query}",
      adaptor: function (payload, response) {
        if (payload.data) {
          payload.data = {
            items: payload.data.map(x => logAdaptor(x, m))
          };
        }
        return payload;
      }
    },
    syncLocation: false,
    initFetch: false,
    loadDataOnce: true,
    headerToolbar: [
      {
        type: "search-box",
        name: "query",
        align: "right",
        placeholder: "query",
        onEvent: {
          search: {
            actions: [
              {
                actionType: "broadcast",
                args: {
                  eventName: eventName
                }
              }
            ]
          }
        }
      }
    ],
    onEvent: tabEventCallback,
    columns: m.fields.map(f => {
      let item = {
        name: f.name,
        label: f.name,
        disabled: true,
        sortable: true,
        searchable: true
      }
      if (f.type == "time") {
        item.type = "input-datetime";
        item.inputFormat = "YYYY/MM/DD HH:mm:ss"
      }
      return item;
    })
  };
}

function logAdaptor(l, m) {
  m.fields.forEach(f => {
    if (f.tag_name != "" && !(f.name in l.data)) {
      l.data[f.name] = l.tags.filter(x => x.label == f.tag_name)[0].value;
    }
    if (f.type == "string" && typeof l.data[f.name] == "object") {
      l.data[f.name] = JSON.stringify(l.data[f.name]);
    }
  });
  return l.data;
}