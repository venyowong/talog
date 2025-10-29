let metricBody = {
    "title": "Metric",
    "body": [
        {
            label: "Index",
            type: "select",
            name: "index",
            source: `./metric/index/list?token=${token}&type=1`
        },
        {
            label: "Name",
            type: "select",
            name: "name",
            source: './metric/names?index=${index}&token=' + token
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
            target: "metricSparkline"
        },
        {
            type: "chart",
            name: "metricSparkline",
            initFetch: false,
            api: "./metric/sparkline?index=${index}&name=${name}&begin=${begin}&end=${end}&token=" + token,
            config: {
                xAxis: {
                    type: "category",
                    data: "${times}"
                },
                yAxis: {
                    type: "value"
                },
                series: [
                    {
                        data: "${line}",
                        type: "line"
                    }
                ]
            }
        }
    ]
};