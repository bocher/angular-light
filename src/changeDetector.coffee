
alight.ChangeDetector = (scope) ->
    root = new Root()

    cd = new ChangeDetector root, scope or {}
    root.topCD = cd
    cd


Root = () ->
    @.watchers =
        any: []
        finishBinding: []
        finishScan: []
        finishScanOnce: []
        onScanOnce: []
    @.status = null

    # helpers
    @.extraLoop = false
    @.finishBinding_lock = false
    @.lateScan = false
    @.topCD = null

    @


Root::destroy = ->
    @.watchers.any.length = 0
    @.watchers.finishBinding.length = 0
    @.watchers.finishScan.length = 0
    @.watchers.finishScanOnce.length = 0
    @.watchers.onScanOnce.length = 0
    if @.topCD
        @.topCD.destroy()


ChangeDetector = (root, scope) ->
    @.scope = scope
    @.locals = scope
    @.root = root
    @.watchList = []
    @.destroy_callbacks = []

    @.parent = null
    @.children = []

    #
    @.rwatchers =
        any: []
        finishScan: []

    return


ChangeDetector::new = (scope, option) ->
    option = option or {}
    parent = @
    scope ?= parent.scope
    cd = new ChangeDetector parent.root, scope
    cd.parent = parent
    if scope is parent.scope
        if option.locals
            Locals = parent._ChildLocals
            if not Locals
                parent._ChildLocals = Locals = ->
                    @.$$root = scope
                    @
                Locals:: = parent.locals
            cd.locals = new Locals()
        else
            cd.locals = parent.locals
    parent.children.push cd

    cd


ChangeDetector::destroy = ->
    cd = @
    root = cd.root
    cd.scope = null

    if cd.parent
        removeItem cd.parent.children, cd

    for fn in cd.destroy_callbacks
        fn()

    for child in cd.children.slice()
        child.destroy()

    cd.destroy_callbacks.length = 0
    for d in cd.watchList
        if d.onStop
            d.onStop()
    cd.watchList.length = 0

    for wa in cd.rwatchers.any
        removeItem root.watchers.any, wa
    cd.rwatchers.any.length = 0
    for wa in cd.rwatchers.finishScan
        removeItem root.watchers.finishScan, wa
    cd.rwatchers.finishScan.length = 0

    if root.topCD is cd
        root.topCD = null
        root.destroy()
    return


WA = (callback) ->
    @.cb = callback

watchAny = (cd, key, callback) ->
    root = cd.root

    wa = new WA callback

    cd.rwatchers[key].push wa
    root.watchers[key].push wa

    return {
        stop: ->
            removeItem cd.rwatchers[key], wa
            removeItem root.watchers[key], wa
    }


###

    option:
        isArray
        readOnly
        oneTime
        deep
        onStop

        watchText



###

watchInitValue = ->

ChangeDetector::watch = (name, callback, option) ->
    option = option or {}
    if option is true
        option =
            isArray: true

    if option.init
        console.warn 'watch.init is depricated'

    cd = @
    root = cd.root
    scope = cd.scope

    if f$.isFunction name
        exp = name
        key = alight.utils.getId()
        isFunction = true
    else
        isFunction = false
        exp = null
        name = name.trim()
        if name[0..1] is '::'
            name = name[2..]
            option.oneTime = true
        key = name
        if key is '$any'
            return watchAny cd, 'any', callback
        if key is '$finishScan'
            return watchAny cd, 'finishScan', callback
        if key is '$finishScanOnce'
            return root.watchers.finishScanOnce.push callback
        if key is '$onScanOnce'
            return root.watchers.onScanOnce.push callback
        if key is '$destroy'
            return cd.destroy_callbacks.push callback
        if key is '$finishBinding'
            return root.watchers.finishBinding.push callback
        if option.deep
            key = 'd#' + key
        else if option.isArray
            key = 'a#' + key
        else
            key = 'v#' + key

    if alight.debug.watch
        console.log '$watch', name

    # create watch object
    isStatic = false
    if not isFunction
        if option.watchText
            exp = option.watchText.fn
        else
            ce = alight.utils.compile.expression(name)
            if ce.filter
                return makeFilterChain cd, ce, callback, option
            isStatic = ce.isSimple and ce.simpleVariables.length is 0
            exp = ce.fn

    if option.deep
        option.isArray = false
    d =
        isStatic: isStatic
        isArray: Boolean option.isArray
        extraLoop: not option.readOnly
        deep: if option.deep is true then 10 else option.deep
        value: watchInitValue
        callback: callback
        exp: exp
        src: '' + name
        onStop: option.onStop or null
        el: option.element or null
        ea: option.elementAttr or null

    if isStatic
        cd.watch '$onScanOnce', ->
            execWatchObject scope, d, d.exp scope
    else
        cd.watchList.push d

    r =
        $: d
        stop: ->
            if option.onStop
                try
                    option.onStop()
                catch e
                    alight.exceptionHandler e, "Error in onStop of watcher: " + name,
                        name
            if d.isStatic
                return
            removeItem cd.watchList, d
        refresh: ->
            value = d.exp cd.locals
            if value and d.deep
                d.value = alight.utils.clone value, d.deep
            else if value and d.isArray
                d.value = value.slice()
            else
                d.value = value

    if option.oneTime
        d.callback = (value) ->
            if value is undefined
                return
            r.stop()
            callback value
    r


ChangeDetector::watchGroup = (keys, callback) ->
    cd = @
    if not callback and f$.isFunction keys
        callback = keys
        keys = null

    planned = false
    group = ->
        if planned
            return
        planned = true
        cd.watch '$onScanOnce', ->
            planned = false
            callback()
    if keys
        for key in keys
            cd.watch key, group
    group


get_time = do ->
    if window.performance
        return ->
            Math.floor performance.now()
    ->
        (new Date()).getTime()


notEqual = (a, b) ->
    if a is null or b is null
        return true
    ta = typeof a
    tb = typeof b
    if ta isnt tb
        return true
    if ta is 'object'
        if a.length isnt b.length
            return true
        for v, i in a
            if v isnt b[i]
                return true
    false


execWatchObject = (scope, w, value) ->
    if w.el
        if w.ea
            w.el.setAttribute w.ea, value
        else
            w.el.nodeValue = value
    else
        w.callback.call scope, value
    return


displayError = (e, cd, w, option) ->
    args =
        src: w.src
        scope: cd.scope
        locals: cd.locals
    if w.el
        args.element = w.el
    if option is 1
        text = '$scan, error in callback: '
    else
        text = '$scan, error in expression: '
    alight.exceptionHandler e, text + w.src, args

ErrorValue = ->


scanCore = (topCD, result) ->
    root = topCD.root
    extraLoop = false
    changes = 0
    total = 0

    if not topCD
        return

    queue = []
    index = 0
    cd = topCD
    while cd
        locals = cd.locals

        # default watchers
        total += cd.watchList.length
        for w in cd.watchList.slice()
            last = w.value
            try
                value = w.exp locals
            catch e
                value = ErrorValue
            if last isnt value
                mutated = false
                if w.isArray
                    a0 = Array.isArray last
                    a1 = Array.isArray value
                    if a0 is a1
                        if a0
                            if notEqual last, value
                                mutated = true
                                w.value = value.slice()
                        else
                            mutated = true
                            w.value = value
                    else
                        mutated = true
                        if a1
                            w.value = value.slice()
                        else
                            w.value = value
                else if w.deep
                    if not alight.utils.equal last, value, w.deep
                        mutated = true
                        w.value = alight.utils.clone value, w.deep
                else
                    mutated = true
                    w.value = value

                if mutated
                    mutated = false

                    if value is ErrorValue
                        displayError e, cd, w
                    else
                        changes++

                        try
                            if w.el
                                if w.ea
                                    if value?
                                        w.el.setAttribute w.ea, value
                                    else
                                        w.el.removeAttribute w.ea
                                else
                                    w.el.nodeValue = value
                            else
                                if last is watchInitValue
                                    last = undefined
                                if w.callback.call(cd.scope, value, last) isnt '$scanNoChanges'
                                    if w.extraLoop
                                        extraLoop = true
                        catch e
                            displayError e, cd, w, 1

                if alight.debug.scan > 1
                    console.log 'changed:', w.src
        queue.push.apply queue, cd.children
        cd = queue[index++]

    result.total = total
    result.changes = changes
    result.extraLoop = extraLoop
    return


ChangeDetector::digest = ->
    root = @.root
    mainLoop = 10
    totalChanges = 0

    if alight.debug.scan
        start = get_time()

    result =
        total: 0
        changes: 0
        extraLoop: false
        src: ''
        scope: null
        element: null

    while mainLoop
        mainLoop--
        root.extraLoop = false

        # take onScanOnce
        if root.watchers.onScanOnce.length
            onScanOnce = root.watchers.onScanOnce.slice()
            root.watchers.onScanOnce.length = 0
            for callback in onScanOnce
                callback.call root

        scanCore @, result
        totalChanges += result.changes

        if not result.extraLoop and not root.extraLoop and not root.watchers.onScanOnce.length
            break
    if alight.debug.scan
        duration = get_time() - start
        console.log "$scan: loops: (#{10-mainLoop}), last-loop changes: #{result.changes}, watches: #{result.total} / #{duration}ms"
    result.mainLoop = mainLoop
    result.totalChanges = totalChanges
    result


ChangeDetector::scan = (cfg) ->
    root = @.root
    cfg = cfg or {}
    if f$.isFunction cfg
        cfg =
            callback: cfg
    if cfg.callback
        root.watchers.finishScanOnce.push cfg.callback
    if cfg.late
        if root.lateScan
            return
        root.lateScan = true
        alight.nextTick ->
            if root.lateScan
                root.topCD.scan()
        return
    if root.status is 'scaning'
        root.extraLoop = true
        return
    root.lateScan = false
    root.status = 'scaning'

    if root.topCD
        result = root.topCD.digest()
    else
        result = {}

    if result.totalChanges
        for cb in root.watchers.any
            cb()

    root.status = null
    for callback in root.watchers.finishScan
        callback()

    # take finishScanOnce
    finishScanOnce = root.watchers.finishScanOnce.slice()
    root.watchers.finishScanOnce.length = 0
    for callback in finishScanOnce
        callback.call root

    if result.mainLoop is 0
        throw 'Infinity loop detected'

    result


# redirects
alight.core.ChangeDetector = ChangeDetector

ChangeDetector::compile = (expression, option) ->
    alight.utils.compile.expression(expression, option).fn

ChangeDetector::setValue = (name, value) ->
    cd = @
    fn = cd.compile name + ' = $value',
        input: ['$value']
        no_return: true
    try
        fn cd.locals, value
    catch e
        msg = "can't set variable: #{name}"
        if alight.debug.parser
            console.warn msg
        if (''+e).indexOf('TypeError') >= 0
            rx = name.match(/^([\w\d\.]+)\.[\w\d]+$/)
            if rx and rx[1]
                # try to make a path
                locals = cd.locals
                for key in rx[1].split '.'
                    if locals[key] is undefined
                        locals[key] = {}
                    locals = locals[key]
                try
                    fn cd.locals, value
                    return
                catch

        alight.exceptionHandler e, msg,
            name: name
            value: value

ChangeDetector::eval = (exp) ->
    fn = @.compile exp
    fn @.locals

ChangeDetector::getValue = (name) ->
    @.eval name
