({
    invoke: function(component) {
        var url = window.location.href;
        component.set('v.url',url);
    }
})