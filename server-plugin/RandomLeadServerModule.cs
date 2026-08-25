using AssettoServer.Server.Plugin;
using Autofac;
using Microsoft.Extensions.Hosting;

namespace RandomLeadServerPlugin;

public sealed class RandomLeadServerModule : AssettoServerModule<RandomLeadServerConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<RandomLeadServer>().AsSelf().As<IHostedService>().SingleInstance();
    }
}
