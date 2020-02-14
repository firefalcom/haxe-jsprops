import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.Tools;
using Lambda;

private typedef SuperClass = Null<{ t:Ref<ClassType>, params:Array<Type> }>;

class JsProp
{
	public static macro function marked() : Array<Field>
	{
		if (Context.defined("display")) return null;

		var klass = Context.getLocalClass().get();
		var fields = Context.getBuildFields();

		if (Context.defined("js"))
		{
			var codes = [];
			for (field in fields)
			{
				if (hasMeta(field, ":property"))
				{
					var t = getDefinePropertyCode(klass, field, true, true);
					if (t != null) codes.push(t);
				}
			}
			if (codes.length > 0)
			{
				addDefinePropertyCode(fields, klass.superClass, codes);
				return fields;
			}
		}
		return null;
	}

	public static macro function all() : Array<Field>
	{
		if (Context.defined("display")) return null;

		var klass = Context.getLocalClass().get();
		var fields = Context.getBuildFields();

		if (Context.defined("js"))
		{
			var codes = [];
			for (field in fields)
			{
				switch (field.kind)
				{
					case FieldType.FProp(_, _, _, _):
						var t = getDefinePropertyCode(klass, field, false, false);
						if (t != null) codes.push(t);
					case _:
				}
			}
			if (codes.length > 0)
			{
				addDefinePropertyCode(fields, klass.superClass, codes);
				return fields;
			}
		}
		return null;
	}

	static function addDefinePropertyCode(fields:Array<Field>, superClass:SuperClass, codes:Array<Expr>)
	{
		var code = macro $b{codes};
		prependCode(getStaticInitFunction(fields), code);
	}

	static function getDefinePropertyCode(klass, field:Field, fixGetterSetter:Bool, fatalNoSupported:Bool) : Expr
	{
		switch (field.kind)
		{
			case FieldType.FProp(get, set, t, e):
				var getter = "get_" + field.name;
				var setter = "set_" + field.name;

				switch ([ get, set, hasMeta(field, ":isVar")])
				{
					case [ "get", "set", false ]:
						ensureNoExpr(e, field.pos);
						if (fixGetterSetter) field.kind = FieldType.FProp("default", "default", t, e);
						return macro (untyped Object).defineProperty(
							(untyped $i{klass.name}).prototype,
							$v{field.name},
							{
								get: (untyped $i{klass.name}).prototype.$getter,
								set: (untyped $i{klass.name}).prototype.$setter
							}
							);


					case [ "get", "never", false ]:
						ensureNoExpr(e, field.pos);
						if (fixGetterSetter) field.kind = FieldType.FProp("default", "never", t, e);
						return macro (untyped Object).defineProperty(
							(untyped $i{klass.name}).prototype,
							$v{field.name},
							{
								get:(untyped $i{klass.name}).prototype.$getter
							});

					case [ "never", "set", false ]:
						ensureNoExpr(e, field.pos);
						if (fixGetterSetter) field.kind = FieldType.FProp("never", "default", t, e);
						return macro (untyped Object).defineProperty(
							(untyped $i{klass.name}).prototype,
							$v{field.name},
							{
								set:(untyped $i{klass.name}).prototype.$setter
							}
							);

					case [ "default"|"null"|"never", "default"|"null"|"never", _ ]:
						// nothing to do

					case _:
						if (fatalNoSupported) Context.fatalError("JsProp: unsupported get/set combination. Supported: (get,set), (get,never) and (never,set) all without @:isVar.", field.pos);
				}

			case _:
				if (fatalNoSupported) Context.fatalError("JsProp: unsupported type (must be a property).", field.pos);
		}
		return null;
	}

	static function prependCode(f:Function, code:Expr)
	{
		switch (f.expr.expr)
		{
			case EBlock(exprs):
				exprs.unshift({ expr:code.expr, pos:code.pos });

			case _:
				f.expr = macro { $code; ${f.expr}; };
		}
	}



	static function getStaticInitFunction(fields:Array<Field>) : Function
	{
		var method : Field = null;

		for (field in fields) if (field.name == "__init__") { method = field; break; }

		if (method == null)
		{
			method = createStaticInitMethod( macro { } );
			fields.push(method);
		}

		switch (method.kind)
		{
			case FieldType.FFun(f):
				return f;

			case _:
				Context.fatalError("JsProp: unexpected __init__ method type '" + method.kind + "'.", method.pos);
				return null;
		}
	}

	static function hasMeta(f:{ meta:Metadata }, m:String) : Bool
	{
		if (f.meta == null) return false;
		for (mm in f.meta)
		{
			if (mm.name == m) return true;
		}
		return false;
	}

	static function createStaticInitMethod( expr:Expr) : Field
	{
		return
		{
			  name: "__init__"
			, access: [ Access.APrivate, Access.AStatic ]
			, kind: FieldType.FFun({ args:[], ret:macro:Void, expr:expr, params:[] })
			, pos: expr.pos
		};
	}

	static function ensureNoExpr(e:Null<Expr>, pos:Position)
	{
		if (e != null)
		{
			Context.fatalError("Default value is not supported here.", pos);
		}
	}
}
