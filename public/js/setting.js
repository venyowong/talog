let settingBody = {
    "title": "设置",
    "body": [
        {
            title: "删除已保存的查询",
            type: "form",
            api: {
                url: "./setting/query/delete?name=${queryName}&token=" + token,
                method: "POST"
            },
            body: [
                {
                    label: "已保存的查询",
                    type: "select",
                    name: "queryName",
                    source: `./setting/query/list?token=${token}`
                }
            ],
            submitText: "删除",
            reload: "queryName"
        },
        {
          title: "删除 Index",
          type: "form",
          api: {
            url: "./index/remove?index=${index}&token=" + token,
            method: "POST"
          },
          body: [
            {
              label: "Index",
              type: "select",
              name: "index",
              source: `./log/index/list?token=${token}`
            }
          ],
          submitText: "删除",
          reload: "index"
        },
        {
          title: "删除 Metric Index",
          type: "form",
          api: {
            url: "./metric/index/delete?type=${metricType}&index=${metricIndex}&token=" + token,
            method: "POST"
          },
          body: [
            {
              label: "类型",
              type: "select",
              name: "metricType",
              value: 0,
              options: [
                {
                  label: "PageView",
                  value: 0
                },
                {
                  label: "Metric",
                  value: 1
                }
              ]
            },
            {
              label: "Index",
              type: "select",
              name: "metricIndex",
              source: "./metric/index/list?type=${metricType}&token=" + token
            }
          ],
          submitText: "删除",
          reload: "metricIndex"
        },
        {
            title: "建议",
            type: "form",
            body: {
                type: "service",
                api: "./index/suggest?token=" + token,
                body: {
                    type: "json",
                    source: "${suggestion}"
                }
            }
        }
    ]
};