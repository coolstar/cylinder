#import "luashit.h"
#import "lua/lauxlib.h"
#import "macros.h"

#define LOG_DIR @"/var/mobile/Library/Logs/Cylinder/"
#define LOG_PATH LOG_DIR"errors.log"

static lua_State *L = NULL;

static int *_scripts = NULL;
static const char **_scriptNames = NULL;
static int _scriptCount;

static int l_transform_rotate(lua_State *L);
static int l_transform_translate(lua_State *L);
static int l_push_base_transform(lua_State *L);
static int l_set_transform(lua_State *L, UIView *self); //-1 = transform
static int l_get_transform(lua_State *L, UIView *self); //pushes transform to top of stack
static int l_uiview_index(lua_State *L);
static int l_uiview_setindex(lua_State *L);
static int l_include(lua_State *L);


void write_error(const char *error);

static void remove_script(int index)
{
    for(int i = index + 1; i < _scriptCount; i++)
    {
        _scripts[i - 1] = _scripts[i];
        _scriptNames[i - 1] = _scriptNames[i];
    }
    _scriptCount--;
}

void post_notification(const char *script, BOOL broken)
{
    if(script != NULL)
    {
        [[[NSString stringWithFormat:@"%s\n%d", script, broken] dataUsingEncoding:NSUTF8StringEncoding] writeToFile:LOG_DIR".errornotify" atomically:true];
        CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterPostNotification(r, CFSTR("luaERROR"), NULL, NULL, true);
    }
}

void close_lua()
{
    if(L != NULL) lua_close(L);
    L = NULL;
}

static void create_state()
{
    //if we are reloading, close the state
    if(L != NULL) lua_close(L);

    //create state
    L = luaL_newstate();

    //set globals
    lua_pushcfunction(L, l_include);
    lua_setglobal(L, "include");
    lua_pushcfunction(L, l_include);
    lua_setglobal(L, "dofile");

    lua_newtable(L);
    l_push_base_transform(L);
    lua_setglobal(L, "BASE_TRANSFORM");

    //set UIView metatable
    luaL_newmetatable(L, "UIView");

    lua_pushcfunction(L, l_uiview_index);
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, l_uiview_setindex);
    lua_setfield(L, -2, "__newindex");

    lua_pop(L, 1);
}

int open_script(const char *script)
{
    int func = -1;

    const char *path = [NSString stringWithFormat:@CYLINDER_DIR"%s.lua", script].UTF8String;

    //load our file and save the function we want to call
    if(luaL_loadfile(L, path) != LUA_OK || lua_pcall(L, 0, 1, 0) != 0)
    {
        write_error(lua_tostring(L, -1));
        post_notification(script, true);
    }
    else if(!lua_isfunction(L, -1))
    {
        write_error([NSString stringWithFormat:@"error opening %s: result must be a function", script].UTF8String);
        post_notification(script, true);
    }
    else
    {
        lua_pushvalue(L, -1);
        func = luaL_ref(L, LUA_REGISTRYINDEX);
        post_notification(script, false);
    }

    lua_pop(L, 1);

    return func;
}

BOOL init_lua(const char *script)
{
    create_state();
    if(script == NULL) script = "Cube (inside)";

    int func = open_script(script);

    if(_scripts != NULL) free(_scripts);
    if(_scriptNames != NULL) free(_scriptNames);

    if(func != -1)
    {
        _scripts = (int *)malloc(sizeof(int));
        _scriptNames = (const char **)malloc(sizeof(char *));
        _scripts[0] = func;
        _scriptNames[0] = script;
        _scriptCount = 1;
        return true;
    }
    else
    {
        _scripts = NULL;
        _scriptNames = NULL;
        _scriptCount = 0;
        return false;
    }
}

BOOL init_lua_random()
{
    create_state();

    NSArray *scripts = [NSFileManager.defaultManager contentsOfDirectoryAtPath:@CYLINDER_DIR error: nil];
    if(_scripts != NULL) free(_scripts);
    if(_scriptNames != NULL) free(_scriptNames);
    _scriptCount = 0;
    if(scripts.count == 0)
    {
        _scripts = NULL;
        _scriptNames = NULL;
        return false;
    }
    _scripts = (int *)malloc(scripts.count*sizeof(int));
    _scriptNames = (const char **)malloc(scripts.count*sizeof(char *));
    for(int i = 0; i < scripts.count; i++)
    {
        char *script = (char *)[[scripts objectAtIndex:i] UTF8String];
        int len = strlen(script);
        if(len > 4 && strcmp(script, "EXAMPLE.lua") != 0 && !strcmp(script + sizeof(char)*(len - 4), ".lua"))
        {
            script[len - 4] = '\0';
            int func = open_script((const char *)script);
            if(func != -1)
            {
                _scripts[_scriptCount] = func;
                _scriptNames[_scriptCount] = script;
                _scriptCount++;
            }
        }
    }
    if(_scriptCount == 0)
    {
        free(_scripts);
        free(_scriptNames);
        return false;
    }
    return true;
}

static int l_include(lua_State *L)
{
    if(!lua_isstring(L, 1))
    {
        lua_pushstring(L, "argument must be a string");
        return lua_error(L);
    }
    const char *filename = lua_tostring(L, 1);
    const char *path = [@CYLINDER_DIR stringByAppendingPathComponent:[NSString stringWithUTF8String:filename]].UTF8String;

    if(luaL_loadfile(L, path) != LUA_OK || lua_pcall(L, 0, 1, 0) != 0)
    {
        return luaL_error(L, "%s", lua_tostring(L, -1));
    }

    return 1;
}


void write_error(const char *error)
{
    if(![NSFileManager.defaultManager fileExistsAtPath:LOG_PATH isDirectory:nil])
    {
        if(![NSFileManager.defaultManager fileExistsAtPath:LOG_DIR isDirectory:nil])
            [NSFileManager.defaultManager createDirectoryAtPath:LOG_DIR withIntermediateDirectories:false attributes:nil error:nil];
        [[NSFileManager defaultManager] createFileAtPath:LOG_PATH contents:nil attributes:nil];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:LOG_PATH];
    [fileHandle seekToEndOfFile];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"[yyyy-MM-dd HH:mm:ss] "];
    NSString *dateStr = [dateFormatter stringFromDate:NSDate.date];

    [fileHandle writeData:[dateStr dataUsingEncoding:NSUTF8StringEncoding]];
    [fileHandle writeData:[NSData dataWithBytes:error length:(strlen(error) + 1)]];
    [fileHandle writeData:[NSData dataWithBytes:"\n" length:2]];
    [fileHandle closeFile];
}

static void push_view(UIView *view)
{
    lua_pushlightuserdata(L, view);
    luaL_getmetatable(L, "UIView");
    lua_setmetatable(L, -2);
}

BOOL manipulate(UIView *view, float offset, float width, float height, u_int32_t rand)
{
    if(L == NULL || _scriptCount == 0) return false;

    int funcIndex = rand % _scriptCount;
    lua_rawgeti(L, LUA_REGISTRYINDEX, _scripts[funcIndex]);

    push_view(view);
    lua_pushnumber(L, offset);
    lua_pushnumber(L, width);
    lua_pushnumber(L, height);

    view.layer.transform = CATransform3DIdentity;
    view.alpha = 1;
    for(UIView *v in view.subviews)
    {
        v.layer.transform = CATransform3DIdentity;
        view.alpha = 1;
    }

    if(lua_pcall(L, 4, 1, 0) != 0)
    {
        write_error(lua_tostring(L, -1));
        lua_pop(L, 1);
        post_notification(_scriptNames[funcIndex], true);
        remove_script(funcIndex);
        if(_scriptCount == 0) close_lua();
        return manipulate(view, offset, width, height, rand);
    }
    else
    {
        lua_pop(L, 1);
        return true;
    }
}


static int l_uiview_setindex(lua_State *L)
{
    UIView *self = (UIView *)lua_touserdata(L, 1);
    if(lua_isstring(L, 2))
    {
        const char *key = lua_tostring(L, 2);
        if(!strcmp(key, "alpha"))
        {
            if(!lua_isnumber(L, 3))
                return luaL_error(L, "alpha must be a number");

            self.alpha = lua_tonumber(L, 3);
        }
        else if(!strcmp(key, "transform"))
        {
            lua_pushvalue(L, 3);
            int result = l_set_transform(L, self);
            lua_pop(L, 1);
            return result;
        }
    }
    return 0;
}

static int l_uiview_index(lua_State *L)
{
    UIView *self = (UIView *)lua_touserdata(L, 1);
    if(lua_isnumber(L, 2)) //if it's a number, return the subview
    {
        int index = lua_tonumber(L, 2) - 1;
        if(index < self.subviews.count)
        {
            push_view([self.subviews objectAtIndex:index]);
            return 1;
        }
    }
    else if(lua_isstring(L, 2))
    {
        const char *key = lua_tostring(L, 2);

        if(!strcmp(key, "subviews"))
        {
            lua_newtable(L);
            for(int i = 0; i < self.subviews.count; i++)
            {
                lua_pushnumber(L, i+1);
                push_view([self.subviews objectAtIndex:i]);
                lua_settable(L, -3);
            }
            return 1;
        }
        else if(!strcmp(key, "alpha"))
        {
            lua_pushnumber(L, self.alpha);
            return 1;
        }
        else if(!strcmp(key, "transform"))
        {
            return l_get_transform(L, self);
        }
        else if(!strcmp(key, "rotate"))
        {
            lua_pushcfunction(L, l_transform_rotate);
            return 1;
        }
        else if(!strcmp(key, "translate"))
        {
            lua_pushcfunction(L, l_transform_translate);
            return 1;
        }
    }

    return 0;
}

#define CHECK_UIVIEW(STATE, INDEX) \
    if(!lua_isuserdata(STATE, INDEX) || ![(NSObject *)lua_touserdata(STATE, INDEX) isKindOfClass:UIView.class]) \
        return luaL_error(STATE, "first argument must be a view")


static int l_transform_rotate(lua_State *L)
{
    CHECK_UIVIEW(L, 1);

    UIView *self = (UIView *)lua_touserdata(L, 1);

    CATransform3D transform = self.layer.transform;
    float pitch = 0, yaw = 0, roll = 0;
    if(!lua_isnumber(L, 3))
        roll = 1;
    else
    {
        pitch = lua_tonumber(L, 3);
        yaw = lua_tonumber(L, 4);
        roll = lua_tonumber(L, 5);
    }

    if(fabs(pitch) > 0.01 || fabs(yaw) > 0.01)
        transform.m34 = -0.002;
    transform = CATransform3DRotate(transform, lua_tonumber(L, 2), pitch, yaw, roll);
    self.layer.transform = transform;

    return 0;
}
static int l_transform_translate(lua_State *L)
{
    CHECK_UIVIEW(L, 1);

    UIView *self = (UIView *)lua_touserdata(L, 1);

    CATransform3D transform = self.layer.transform;
    float x = lua_tonumber(L, 2), y = lua_tonumber(L, 3), z = lua_tonumber(L, 4);
    float oldm34 = transform.m34;
    if(fabs(z) > 0.01)
        transform.m34 = -0.002;
    transform = CATransform3DTranslate(transform, x, y, z);
    transform.m34 = oldm34;

    self.layer.transform = transform;

    return 0;
}

const static char *ERR_MALFORMED = "malformed transformation matrix";

static float POPA_T(lua_State *L, int index)
{
    lua_pushnumber(L, index);
    lua_gettable(L, -2);
    if(!lua_isnumber(L, -1))
        return luaL_error(L, ERR_MALFORMED);

    float result = lua_tonumber(L, -1);
    lua_pop(L, 1);
    return result;
}

#define CALL_TRANSFORM_MACRO(F, ...)\
    F(m11, ## __VA_ARGS__);\
    F(m12, ## __VA_ARGS__);\
    F(m13, ## __VA_ARGS__);\
    F(m14, ## __VA_ARGS__);\
    F(m21, ## __VA_ARGS__);\
    F(m22, ## __VA_ARGS__);\
    F(m23, ## __VA_ARGS__);\
    F(m24, ## __VA_ARGS__);\
    F(m31, ## __VA_ARGS__);\
    F(m32, ## __VA_ARGS__);\
    F(m33, ## __VA_ARGS__);\
    F(m34, ## __VA_ARGS__);\
    F(m41, ## __VA_ARGS__);\
    F(m42, ## __VA_ARGS__);\
    F(m43, ## __VA_ARGS__);\
    F(m44, ## __VA_ARGS__)

#define BASE_TRANSFORM_STEP(M, LUASTATE, I, TRANSFORM)\
    lua_pushnumber(LUASTATE, ++I);\
    lua_pushnumber(LUASTATE, TRANSFORM.M);\
    lua_settable(LUASTATE, -3)

static int l_push_base_transform(lua_State *L)
{
    int i = 0;
    CALL_TRANSFORM_MACRO(BASE_TRANSFORM_STEP, L, i, CATransform3DIdentity);
    return 1;
}

#define FILL_TRANSFORM(M, LUASTATE, I, TRANSFORM)\
    lua_pushnumber(LUASTATE, ++I);\
    lua_gettable(LUASTATE, -3);\
    if(!lua_isnumber(LUASTATE, -1))\
        return luaL_error(LUASTATE, ERR_MALFORMED);\
    TRANSFORM.M = lua_tonumber(LUASTATE, -1);\
    lua_pop(LUASTATE, 1)

static int l_set_transform(lua_State *L, UIView *self) //-1 = transform
{
    if(!lua_istable(L, -1))
        return luaL_error(L, "transform must be a table");
    lua_len(L, -1);
    if(lua_tonumber(L, -1) != 16)
        return luaL_error(L, ERR_MALFORMED);
    lua_pop(L, 1);

    CATransform3D transform;
    int i = 0;
    CALL_TRANSFORM_MACRO(FILL_TRANSFORM, L, i, transform);
    self.layer.transform = transform;

    return 0;
}

#define PUSH_TRANSFORM(M, LUASTATE, I, TRANSFORM)\
    lua_pushnumber(LUASTATE, ++I);\
    lua_pushnumber(LUASTATE, TRANSFORM.M);\
    lua_settable(LUASTATE, -3)

static int l_get_transform(lua_State *L, UIView *self) //pushes transform to top of stack
{
    lua_newtable(L);
    int i = 0;
    CALL_TRANSFORM_MACRO(PUSH_TRANSFORM, L, i, self.layer.transform);
    return 1;
}
