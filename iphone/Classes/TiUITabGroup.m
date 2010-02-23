/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiUITabGroup.h"
#import "TiUITabProxy.h"
#import "TiUtils.h"
#import "TiUITabController.h"

@implementation TiUITabGroup

DEFINE_EXCEPTIONS

-(void)dealloc
{
	RELEASE_TO_NIL(controller);
	RELEASE_TO_NIL(focused);
	[super dealloc];
}

-(UITabBarController*)tabController
{
	if (controller==nil)
	{
		controller = [[UITabBarController alloc] init];
		controller.delegate = self;
	}
	return controller;
}

-(int)findIndexForTab:(TiProxy*)proxy
{
	if (proxy!=nil)
	{
		int index = 0;
		for (UINavigationController *tc in controller.viewControllers)
		{
			if (tc.delegate == (id)proxy)
			{
				return index;
			}
			index++;
		}
	}
	return -1;
}

#pragma mark Dispatching focus change

- (void)tabFocusChangeToProxy:(TiUITabProxy *)newFocus;
{
	NSMutableDictionary * event = [NSMutableDictionary dictionaryWithCapacity:4];

	NSArray * tabArray = [controller viewControllers];

	int previousIndex = -1;
	int index = -1;

	if (focused != nil)
	{
		[event setObject:focused forKey:@"previousTab"];
		previousIndex = [tabArray indexOfObject:[(TiUITabProxy *)focused controller]];
	}
	
	if (newFocus != nil)
	{
		[event setObject:newFocus forKey:@"tab"];
		index = [tabArray indexOfObject:[(TiUITabProxy *)newFocus controller]];
	}

	[event setObject:NUMINT(previousIndex) forKey:@"previousIndex"];
	[event setObject:NUMINT(index) forKey:@"index"];

	if ([self.proxy _hasListeners:@"blur"])
	{
		[self.proxy fireEvent:@"blur" withObject:event];
	}
	if ([focused _hasListeners:@"blur"])
	{
		[focused fireEvent:@"blur" withObject:event];
	}
	
	RELEASE_TO_NIL(focused);
	focused = [newFocus retain];
	[self.proxy replaceValue:focused forKey:@"activeTab" notification:NO];

	if ([self.proxy _hasListeners:@"focus"])
	{
		[self.proxy fireEvent:@"focus" withObject:event];
	}
	if ([focused _hasListeners:@"focus"])
	{
		[focused fireEvent:@"focus" withObject:event];
	}
}


#pragma mark More tab delegate

-(void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated	
{
	NSArray * moreViewControllerStack = [navigationController viewControllers];
	int stackHeight = [moreViewControllerStack count];
	if (stackHeight > 1)
	{
		UIViewController * rootController = [moreViewControllerStack objectAtIndex:1];
		if ([rootController respondsToSelector:@selector(tab)])
		{
			[[rootController tab] handleWillShowViewController:viewController];
		}
	}
}


- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	NSArray * moreViewControllerStack = [navigationController viewControllers];
	int stackHeight = [moreViewControllerStack count];
	if (stackHeight < 2) //No more faux roots.
	{
		if (focused != nil)
		{
			[self tabFocusChangeToProxy:nil];
		}
		return;
	}

	UIViewController * rootController = [moreViewControllerStack objectAtIndex:1];
	if (![rootController respondsToSelector:@selector(tab)])
	{
		return;
	}
	
	TiUITabProxy * tabProxy = [rootController tab];
	if (stackHeight == 2)	//One for the picker, one for the faux root.
	{
		if (tabProxy != focused)
		{
			[self tabFocusChangeToProxy:tabProxy];
		}
	}

	[tabProxy handleDidShowViewController:viewController];
}

#pragma mark TabBarController Delegates

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
	if ([tabBarController moreNavigationController] == viewController)
	{
		if (self != [(UINavigationController *)viewController delegate])
		{
			[(UINavigationController *)viewController setDelegate:self];
		}
		NSArray * moreViewControllerStack = [(UINavigationController *)viewController viewControllers];
		if ([moreViewControllerStack count]>1)
		{
			viewController = [moreViewControllerStack objectAtIndex:1];
		}
		else
		{
			viewController = nil;
		}

	}

	[self tabFocusChangeToProxy:(TiUITabProxy *)[(UINavigationController *)viewController delegate]];
}


- (void)tabBarController:(UITabBarController *)tabBarController willEndCustomizingViewControllers:(NSArray *)viewControllers changed:(BOOL)changed
{
	//TODO
}


#pragma mark Public APIs

-(void)setTabs_:(id)tabs
{
	ENSURE_TYPE_OR_NIL(tabs,NSArray);
	
	if (tabs!=nil && [tabs count] > 0)
	{
		NSMutableArray *controllers = [[NSMutableArray alloc] init];
		for (TiUITabProxy *tabProxy in tabs)
		{
			[controllers addObject:[tabProxy controller]];
		}
		[self tabController].viewControllers = controllers;
		[controllers release];
		if (focused == nil)
		{
			focused = [tabs objectAtIndex:0];
			[self.proxy	replaceValue:focused forKey:@"activeTab" notification:NO];
		}
	}
	else
	{
		focused = nil;
		[self.proxy	replaceValue:nil forKey:@"activeTab" notification:NO];
		[self tabController].viewControllers = nil;
	}
}

-(void)setActiveTab_:(id)value
{
	UIViewController *active = nil;
	
	NSArray * tabViewControllers = [[self tabController] viewControllers];

	if ([value isKindOfClass:[TiUITabProxy class]])
	{
		
		TiUITabProxy *tab = (TiUITabProxy*)value;
		for (UIViewController *c in [self tabController].viewControllers)
		{
			if ([[tab controller] isEqual:c])
			{
				active = c;
				break;
			}
		}
	}
	else
	{
		int index = [TiUtils intValue:value];
		if (index >= 0 && index < [[self tabController].viewControllers count])
		{
			active = [[self tabController].viewControllers objectAtIndex:index];
		}
	}
	
	[self tabController].selectedViewController = active;
	[self tabBarController:[self tabController] didSelectViewController:active];
}

-(void)open:(id)args
{
	UIView *view = [self tabController].view;
	[TiUtils setView:view positionRect:[self bounds]];
	[self addSubview:view];

	// on an open, make sure we send the focus event to initial tab
	NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:focused,@"tab",NUMINT(0),@"index",NUMINT(-1),@"previousIndex",[NSNull null],@"previousTab",nil];
	[self.proxy fireEvent:@"focus" withObject:event];
	[focused fireEvent:@"focus" withObject:event];
}

-(void)close:(id)args
{
	[self.proxy setValue:nil forKey:@"activeTab"];
	if (controller!=nil)
	{ 
		for (UIViewController *c in controller.viewControllers)
		{
			UINavigationController *navController = (UINavigationController*)c;
			TiUITabProxy *tab = (TiUITabProxy*)navController.delegate;
			[tab close:nil];
			[tab removeFromTabGroup];
		}
		controller.viewControllers = nil;
	}
	RELEASE_TO_NIL(controller);
	RELEASE_TO_NIL(focused);
}

@end