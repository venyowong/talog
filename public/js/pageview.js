let pageViewBody = {
    "title": "PageView",
    "body": [
        {
            label: "Index",
            type: "select",
            name: "index",
            source: `./metric/index/list?token=${token}&type=0`
        },
        {
            label: "Page",
            type: "select",
            name: "page",
            source: './metric/pg/pages?index=${index}&token=' + token
        },
        {
            "type": "input-date",
            "name": "begin",
            "label": "起始日期",
            value: "-7days",
            format: "YYYY-MM-DD"
        },
        {
            "type": "input-date",
            "name": "end",
            "label": "截止日期",
            value: "today",
            format: "YYYY-MM-DD"
        },
        {
            type: "button",
            label: "刷新",
            actionType: "reload",
            target: "latestPageView,pageViewSparkline"
        },
        {
            type: "service",
            name: "latestPageView",
            initFetch: false,
            api: "./metric/pg/latest?index=${index}&page=${page}&token=" + token,
            body: [
                {
                    type: "flex",
                    justify: "center",
                    items: [
                        {
                            style: {
                                "margin-left": "200px",
                                "margin-right": "200px"
                            },
                            type: "tpl",
                            tpl: "<h1>${latestDate}</h1>"
                        },
                        {
                            style: {
                                "margin-left": "200px",
                                "margin-right": "200px"
                            },
                            type: "tpl",
                            tpl: "<h1>PV: ${latestPV}</h1>"
                        },
                        {
                            style: {
                                "margin-left": "200px",
                                "margin-right": "200px"
                            },
                            type: "tpl",
                            tpl: "<h1>UV: ${latestUV}</h1>"
                        }
                    ]
                }
            ]
        },
        {
            type: "chart",
            name: "pageViewSparkline",
            initFetch: false,
            api: "./metric/pg/sparkline?index=${index}&page=${page}&begin=${begin}&end=${end}&token=" + token,
            config: {
                xAxis: {
                    type: "category",
                    data: "${dates}"
                },
                yAxis: {
                    type: "value"
                },
                series: [
                    {
                        data: "${pvLine}",
                        type: "line"
                    },
                    {
                        data: "${uvLine}",
                        type: "line"
                    }
                ]
            }
        }
    ]
};