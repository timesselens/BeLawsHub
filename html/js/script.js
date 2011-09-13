var belaws = (function($) {
    
    var spincount = 0; // internal spincount locker
    var urlQuerySearch;
    var urlQueryDocUID;
    var urlLang;
    var bodylayout;
    var centerlayout;

    function supports_localstorage() { // private function to check for localStorage {{{
        try {
            return 'localStorage' in window && window['localStorage'] !== null;
        } catch(e) { return false; }
    }// }}}

    return {
        lang: {
            search: { nl: 'BeLaws zoeken', fr: 'chercher BeLaws' },
            inapp: { nl: 'Open in webapp', fr: 'Ouvrir dans webapp' }
        },
        ui: {
            init: function() {// initializes the ui {{{
                belaws.menu.init();
                belaws.ui.bind_events();
                belaws.page.set_form_on_cookie();
                belaws.page.bind_lang_links();
                bodylayout = $('body').css({ position:'absolute', height: '100%', width: '100%' }).layout({ // height: fix layout on jq 161
                    north: {
                        resizable: false,
                        closable: false,
                        spacing_open: 0,
                        width: '100%',
                        size: 44
                    },
                    west: { 
                        size: "25%"
                    },
                    center: {
                        onresize: function() { centerlayout.resizeAll(); }
                    }
                });
                centerlayout = $('div.ui-layout-container').layout({ north: { size: 250 } });
                centerlayout.close('north');
                belaws.state.get_from_url();
                if(urlQuerySearch) { $('input[name=q]').val(unescape(urlQuerySearch[1])); belaws.ui.submit_form(); }
                if(urlQueryDocUID) { belaws.ui.show(urlQueryDocUID[1]); }

            },//}}} 
            bind_events: function() { //{{{
                $("#result tr.entry").live('click',function(e) { belaws.ui.show($(this).attr('rel')); });

                $('ul.panellist input[type="checkbox"]').live('click',function(e) { 
                    belaws.state.rebuild_query_from_checkboxes(); 
                    belaws.state.rebuild_intersect_from_checkboxes();
                    belaws.ui.filter_search_results();
                });

                $('ul.panellist img#add_bookmark').bind('click',function(e) { belaws.state.add_bookmark(); });

                $("ul.panellist ul.historylist li").live('click', function(e) {
                    $('input[name=q]').val($(this).text().trim());
                    belaws.ui.reset();
                    belaws.ui.submit_form();
                    belaws.state.push_to_url();
                });

                $("input[type=submit]").bind('click', function(e) {
                    e.preventDefault();
                    belaws.ui.reset();
                    belaws.state.add_history();
                    belaws.ui.submit_form();
                    belaws.state.push_to_url();
                    return false;
                });

                $("form").bind("submit",function(e) {
                    e.preventDefault();
                    belaws.ui.reset();
                    belaws.ui.submit_form();
                    belaws.state.add_history();
                    belaws.state.push_to_url();
                    return false;
                });

                $('.mainview .header .viewsource').live('click',function(e) {
                    e.preventDefault();
                    var $v = $('.mainview');
                    var doc = $v.data('doc');
                    if($v.is(".sourceview")) {
                        $v.find('.header .viewsource a').html('view source');
                        $v.find('.docbody').html(doc.pretty);
                        $v.removeClass('sourceview');
                    } else {
                        try {
                            $v.find('.docbody').html(doc.body);
                        } catch(e) {
                            
                        }
                        $v.find('.docbody a').bind('click',function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            alert('forbidden');
                            return false;
                        });
                        $v.find('.header .viewsource a').html('view pretty');
                        $v.addClass('sourceview');
                    }

                    return false;
                });
            },//}}}
            render: function(part,q) { // render searchresult in the form of a table row {{{
                var cat_ident = (part.cat || "null").replace(/\W/g,'_').replace(/_+/g,'_');
                return [
                    '<tr class="entry" rel="',part.docuid,'">',
                        '<td class="docdate">', part.docdate, '</td>',
                        '<td class="doctype"><div class="legend ', cat_ident, '"></div></td>',
                        '<td class="doctitle">', part.title, '</td>',
                    '</tr>'
                ].join(''); 
            },//}}}
            render_doc: function() {/*{{{*/
                var $v = $('.mainview').empty();
                var doc = $v.data('doc');
                $v.append([
                          '<div class="header">',
                            '<dl>',
                                '<dt>docuid</dt>', '<dd><span class="docuid">',doc.docuid,'</span></dd>',
                                '<dt>pubdate</dt>', '<dd><span class="pubdate">',doc.pubdate,'</span></dd>',
                            '</dl>',
                            '<ul class="actions">',
                                '<li><span class="viewsource"><a href="#">view source</a></span>',
                                '<li><span class="doclink"><a target="_blank" href="/doc.html?d=',doc.docuid,'">open in tab</a><span></li>',
                            '</ul>',
                          '</div>',
                          '<div style="clear:both"></div>',
                          '<div class="docbody">',
                          '</div>'
                ].join(''));
                $v.find('.docbody').html(doc.pretty);
            },/*}}}*/
            show: function(docuid) { // show the docuid, push the state {{{
                var query = $('input[name=q]').val().trim();
                var lang = $('input[name=lang]').val().trim();
                $('img.spinner').show(); spincount++;
                $.ajax({
                    url: "/api/doc.json",
                    data: { docuid: docuid, q: query, lang: lang },
                    dataType: 'json',
                    success: function(json) {
                        $(".mainview").data('doc',json).empty().scrollTop(0);
                        belaws.ui.render_doc();
                        $("#result tr.selected").removeClass('selected');
                        $("#result tr.entry[rel='"+docuid+"']").addClass('selected');
                        window.history.pushState({},'BeLawsHub', '/app.html?q=' + escape(query) + '&docuid=' + docuid);
                        if(--spincount === 0) { $('img.spinner').hide(); }
                    },
                    error: function() {
                        if(--spincount === 0) { $('img.spinner').hide(); }
                    }
                });
            },//}}}
            append_search_results: function() { // appends search results to top {{{
                var query = $('input[name=q]').val().trim();
                var lang = $('input[name=lang]').val().trim();
                $.ajax({
                    url: "/api/search.json", 
                    data: { q: query, lang: lang },
                    dataType: 'json',
                    success: function(json) {
                        var h = [];
                        for (var key in json) { h.push(belaws.ui.render(json[key],query)); }
                        centerlayout.open('north');
                        if( ! h.length > 0 ) {
                            $("#result").html('<div class="no_results">No results</div>');
                        } else {
			    $("#result").html(h.join(''));
                            if(urlQueryDocUID) { 
                                var docuid = urlQueryDocUID[1];
                                $("#result tr.selected").removeClass('selected');
                                //console.log('docuid %o el %o', docuid, $("tr.entry[rel='"+docuid+"']"));
                                $("#result tr.entry[rel='"+docuid+"']").addClass('selected');
                            }
			}
                        if(--spincount === 0) { $('img.spinner').hide(); }
                    },
                    error: function() {
                        alert('unable to fetch data');
                        if(--spincount === 0) { $('img.spinner').hide(); }
                    }
                });
            }, //}}}
            filter_search_results: function() {/*{{{*/
                $("table#result").hide();
                if(belaws.state.filter) {
                    $("#result tr.entry").hide(); 
                    $.each(belaws.state.filter,function(i,o) {
                        $("#result tr.entry[rel='"+o+"']").show();
                    });
                } else {
                    $("#result tr").show();
                }
                $("table#result").show();
            },/*}}}*/
            append_person_class: function() { // ajax gets person names and appends {{{
                var query = $('input[name=q]').val().trim();
                var lang = $('input[name=lang]').val().trim();
                $.ajax({
                    url: "/api/class/person.json",
                    data: { q: query, lang: lang },
                    dataType: 'json',
                    success: function(json) {
                        $('ul.panellist table.personlist').empty();
                        $.each(json,function(i,o) {
                            var ident = o.name.replace(/[\W\s]/g,'_').replace(/_+/g,'_').toLowerCase();
                            var name = o.name.replace(/\w\S*/g, function(txt){ return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase(); });
                            var $html = $([
                                '<tr>',
                                '<td><input type="checkbox" rel="person" id="',ident,'"/></td>',
                                '<td><label for="',ident,'"><span class="key name">',name,'</span></label></td>',
                                '<td><span class="count">',o.count,'</span></td>',
                                '</tr>'
                            ].join(''));
                            // console.log("docuids %o", o.docuids);
                            $html.find('input').data('docuids',o.docuids);
                            $html.find('span.count').data('count_orig',o.count);
                            $('ul.panellist table.personlist').append($html);
                        });
                            
                    }
                });
            },// }}}
            append_cat_class: function() { // {{{
                var query = $('input[name=q]').val().trim();
                var lang = $('input[name=lang]').val().trim();
                $.ajax({
                    url: "/api/class/cat.json",
                    data: { q: query, lang: lang },
                    dataType: 'json',
                    success: function(json) {
                        $('ul.panellist table.catlist').empty();
                        $.each(json,function(i,o) {
                            var ident = o.cat.replace(/[\W\s]/g,'_').replace(/_+/g,'_').toLowerCase();
                            var cat = o.cat.replace(/\w\S*/g, function(txt){ return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase(); });
                            var $html = $([
                                '<tr>',
                                '<td><input type="checkbox" rel="cat" id="',ident,'"/></td>',
                                '<td><label for="',ident,'"><span class="key cat">',cat,'</span></label></td>',
                                '<td><span class="count">',o.count,'</span></td>',
                                '</tr>'
                            ].join(''));
                            $html.find('input').data('docuids',o.docuids);
                            $html.find('span.count').data('count_orig',o.count);
                            $('ul.panellist table.catlist').append($html);
                        });
                    }
                });
            }, //}}}
            append_geo_class: function() { // {{{
                var query = $('input[name=q]').val().trim();
                var lang = $('input[name=lang]').val().trim();
                $.ajax({
                    url: "/api/class/geo.json",
                    data: { q: query, lang: lang },
                    dataType: 'json',
                    success: function(json) {
                        $('ul.panellist table.geolist').empty();
                        $.each(json,function(i,o) {
                            var ident = o.geo.replace(/[\W\s]/g,'_').toLowerCase();
                            var geo = o.geo.replace(/\w\S*/g, function(txt){ return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase(); });
                            var $html = $([
                                '<tr>',
                                '<td><input type="checkbox" rel="geo" id="',ident,'"/></td>',
                                '<td><label for="',ident,'"><span class="key geo">',geo,'</span></label></td>',
                                '<td><span class="count">',o.count,'</span></td>',
                                '</tr>'
                            ].join(''));
                            $html.find('input').data('docuids',o.docuids);
                            $html.find('span.count').data('count_orig',o.count);
                            $('ul.panellist table.geolist').append($html);
                        });
                    }
                });
            }, // }}}
            submit_form: function() { // {{{
                var query = $('input[name=q]').val().trim();
                $('img.spinner').show(); spincount++;
                $('ul.panellist table').empty();

                belaws.ui.append_search_results();
                belaws.ui.append_person_class();
                belaws.ui.append_geo_class();
                belaws.ui.append_cat_class();

            }, // }}}
            reset: function() {//{{{
                $(".mainview").empty();
            }//}}}
        },
        page: {
            set_input_on_url: function() {
                var q = window.location.search.substr(1).match(/q=([^&]+)/)[1];
                if(q) {
                    $("input#q").val(unescape(q.replace(/\+/g,' ')));
                }
            },
            set_form_on_cookie: function() {
                try { var urilang = window.location.search.substr(1).match(/lang=(nl|fr)/)[1]; } catch (e) {}
                var lang = urilang || $.cookie('pref_lang');
                $('input#lang').val(lang);
                $('input#search').attr('value',belaws.lang.search[lang]);
                $('input#direct').attr('value',belaws.lang.inapp[lang]);
            },
            bind_lang_links: function() {
                var loc = window.location.href;
                $('p.lang a[rel=nl]').attr('href',loc.replace('lang=fr','lang=nl'));
                $('p.lang a[rel=fr]').attr('href',loc.replace('lang=nl','lang=fr'));

                $('p.lang a').bind('click',function(e) {
                    //e.preventDefault;
                    var lang = $(e.target).attr('rel');
                    $('input#lang').attr('value',lang);
                    $.cookie('pref_lang', lang, { path: '/', expires: 7 });
                    $('input#search').attr('value',belaws.lang.search[lang]);
                    $('input#direct').attr('value',belaws.lang.inapp[lang]);
                    return true;
                });
            }
        },
        frontpage: {
            init: function() {/*{{{*/
                belaws.page.set_form_on_cookie();
                belaws.page.bind_lang_links();

                $('input#direct').bind('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var val = $('input#q').val();
                    if(val) {
                        window.location = '/app.html?q=' + val + '&lang=' + $('input#lang').val();
                    }
                });
            }/*}}}*/
        },
        searchpage: {
            init: function() {
                belaws.page.set_form_on_cookie();
                belaws.page.bind_lang_links();
                belaws.page.set_input_on_url();
            }
        },
        menu: {/*{{{*/
            init: function() {
                var $h1 = $('h1.dropdown');
                var top = $h1.position().top;
                var left = $h1.position().left;
                var height = $h1.outerHeight();
                $h1.bind('click',function(e) {
                    $('div.linkmenu').css({top: top + height + 10 , left: left})
                                     .slideDown(function() {
                                            $('body').one('click',function() { $('div.linkmenu').hide(); });
                                     });
                });
            }
        },/*}}}*/
        state: {
            get_from_url: function() { // set internal state from url {{{
                var searchpairs = window.location.search.substr(1).split(/&/);
                var params = {};
                for (var i=0; i < searchpairs.length; i++) {
                    var pair = searchpairs[i].split(/=/);
                    params[pair[0]] = pair[1];
                }
                if(params.q) {
                    urlQuerySearch = params.q ? [null, params.q] : null; // expects array
                    urlQueryDocUID = params.docuid ? [null, params.docuid] : null; // expects array
                } else {
                    urlQuerySearch = window.location.toString().match(/\/s\/([^\/]*)/);
                    urlQueryDocUID = window.location.toString().match(/\/d\/([\w\d\-\/]+)/);
                } 

                if(params.lang) {
                    urlLang = params.lang;
                    $('input#lang').attr('value', params.lang);
                }
                
                return {s: urlQuerySearch, d:urlQueryDocUID, l: urlLang };
            },//}}}  
            push_to_url: function(query) {//{{{
                var query = query || $('input[name=q]').val().trim();
                window.history.pushState({},'BeLawsHub', '/app.html?q=' + escape(query) );
            },//}}}
            rebuild_query_from_checkboxes: function() { // {{{
                var re = new RegExp('\\w+\\s*:\\s*[^\\s]+\s*','g');
                var $input = $("input#q");

                $input.val( $input.val().replace(re, '') );

                $('ul.panellist input[type="checkbox"]').each(function(i,o) {
                    var rel = $(this).attr('rel');
                    var id = $(this).attr('id');

                    if( $(this).is(":checked") ) {
                        $input.val( ($input.val() + ' ' + rel + ':' + id + ' ').replace(/\s+/g,' ') );
                    }
                });
            }, //}}}
            rebuild_intersect_from_checkboxes: function() { // {{{

                var all = [];

                $('ul.panellist input[type="checkbox"]').each(function(i,o) {
                    var rel = $(this).attr('rel');
                    var id = $(this).attr('id');
                    var docuids = $(this).data('docuids');

                    if( $(this).is(":checked") ) {
                        all.push(docuids); // pushes an array onto the all array
                    }
                });

                var u = {};
                $.each(all,function(i,o){ $.each(o, function(j,p) { u[p] = (u[p] || 0) + 1;  }); });
                var intersect = $.map(u, function(v,k) { if(v === all.length) { return k; } } );
                 
                if($('ul.panellist input[type="checkbox"]:checked').size() > 0) {
                    belaws.state.filter = intersect;
                    $('ul.panellist input[type="checkbox"]').each(function(i,o) {
                        var common = belaws.helper.intersect($(this).data('docuids'),belaws.state.filter).length;
                        var $count = $(this).parent().next().next().find('.count');
                        $count.text(common);
                    });
                } else {
                    belaws.state.filter = null;
                    $('ul.panellist input[type="checkbox"]').each(function(i,o) {
                        var $count = $(this).parent().next().next().find('.count');
                        $count.text($count.data('count_orig'));
                    });
                }



                return intersect;
            }, //}}}
            add_history: function(query) {//{{{
                var query = query || $('input[name=q]').val().trim();
                query = query.replace(/\s*\w+:[^\ ]+\s*/,'').trim();
                var $hl = $('ul.panellist ul.historylist');
                if($hl.find('li:first').text() != query) {
                    $hl.prepend(['<li>',query,'</li>'].join(''));
                }
            },//}}}
        add_bookmark: function() { // {{{
                $('ul.panellist ul.bookmarklist').append([
                    '<li>',
                        '<a href="',window.location.pathname,'">',
                            '<span class="docuid">',unescape(urlQueryDocUID[1]),'</span>',
                            '<span class="search">',unescape(urlQuerySearch[1]),'</span>',
                        '</a>',
                    '</li>'
                ].join(''));
            } // }}}
        },
        helper: {/*{{{*/
            intersect: function(a1,a2){ // TODO: use arguments
                var u = {};
                $.each([a1,a2],function(i,o){ $.each(o, function(j,p) { u[p] = (u[p] || 0) + 1;  }); });
                var intersect = $.map(u, function(v,k) { if(v === 2) { return k; } } );
                return intersect;
            }
        }/*}}}*/
    };
})(jQuery);

// vim: foldmethod=marker ts=4
